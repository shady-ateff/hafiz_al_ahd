# Hafiz Al-Ahd - Clean Architecture Deep Dive

This document provides an in-depth analysis of the **Clean Architecture** implementation in the `hafiz_al_ahd` Flutter project. 

The project strictly adheres to Uncle Bob's Clean Architecture principles combined with Feature-Driven Folder Structure. This ensures separation of concerns, scalability, and testability.

## 📁 High-Level Folder Structure (`lib/`)
The `lib` folder is primarily divided into three main modules:
1.  **`core/`**: Contains application-wide utilities, base error handling (`Failure`, `Exception`), themes, and global services (e.g., `location_service.dart`, `desktop_window_service.dart`).
2.  **`features/`**: The core application workflows. Each distinct feature (`home`, `notifications`, `settings`) is completely isolated and implements its own Clean Architecture layers.
3.  **`app/`**: Application-level initialization (`app.dart`).

---

## 🏗️ Feature Level Breakdown (e.g., `home` Feature)
Every isolated feature inside the `features` directory follows the exact three-layer Clean Architecture model:

### 1. Domain Layer (`domain/`)
**The heart of the application.** It contains the enterprise and application business logic. It has zero dependencies on any external libraries (no UI, no Flutter, no databases) except `dartz` (for functional error handling).
*   **Entities (`entities/`)**: Pure Dart classes representing real-world objects.
    *   *Example*: `PrayerTimesEntity` – holds pure prayer times data (Fajr, Dhuhr, etc.) without knowing how they are fetched.
*   **Repositories (`repositories/`)**: Abstract classes (interfaces) defining the contracts that the Data layer must fulfill. 
    *   *Example*: `PrayerTimesRepo` defines `Future<Either<Failure, PrayerTimesEntity>> getPrayerTimes(...)`.
*   **Use Cases (`usecases/`)**: Application-specific business rules. They execute specific actions by calling the repository interfaces. 
    *   *Example*: `GetPrayerTimesUseCase` takes the `PrayerTimesRepo` as a dependency injection and simply calls its method. It acts as a strict boundary between UI and data logic.

### 2. Data Layer (`data/`)
Responsible for executing the contracts defined by the Domain layer. It handles external data sources (APIs, databases, device sensors).
*   **Models (`models/`)**: Extensions of Domain Entities that include serialization/deserialization logic (e.g., `fromJson`, `toJson`). 
    *   *Example*: `PrayerTimeModel` maps the `adhan` library outputs extending `PrayerTimesEntity`.
*   **Data Sources (`datasources/`)**: The actual implementation of data fetching. Can be divided into Remote and Local.
    *   *Example*: `PrayerTimesLocalDataSource` calculates prayer times using the `adhan` library locally.
*   **Repositories Impl (`repositories/`)**: The concrete implementation of the Domain's repository interface. It decides which data source to call and catches exceptions, transforming them into `Failure` objects for the Domain layer using `dartz`'s `Either`.
    *   *Example*: `PrayerTimesRepoImpl` implements `PrayerTimesRepo`.

### 3. Presentation Layer (`presentation/`)
Responsible solely for rendering the UI and maintaining the specific state of the screen.
*   **State Management (`cubit/`)**: Uses Flutter Bloc/Cubit. The Cubit depends *only* on the Use Cases from the Domain layer. 
    *   *Example*: `PrayerTimesCubit` calls `getPrayerTimesUseCase`, waits for the `Either` result, and emits `PrayerTimesLoaded` or `PrayerTimesError` accordingly. It does not know where the data comes from (API or Local), maintaining full decoupling.
*   **UI / Widgets (`screens/`, `widgets/`)**: Flutter widgets that consume the Cubit states.
    *   *Example*: `home_screen.dart` listens to `PrayerTimesCubit` and renders `PrayerTimesGrid` when the load is successful.

---

## 🔄 The Data Flow Example (Fetching Prayer Times)
1.  **UI Event**: User opens app or clicks a button in `home_screen.dart`.
2.  **Cubit Call**: UI calls `fetchPrayerTimes()` in `PrayerTimesCubit`.
3.  **Use Case Execution**: The Cubit calls `getPrayerTimesUseCase.call(...)`.
4.  **Repository Delegation**: The Use Case delegates the call to the abstract `PrayerTimesRepo` interface.
5.  **Repository Impl**: The exact injection `PrayerTimesRepoImpl` receives the call.
6.  **Data Source Call**: The repo calls `PrayerTimesLocalDataSource.getPrayerTimes(...)`.
7.  **Data Processing**: The Data Source calculates times using the `adhan` library, returning a `PrayerTimeModel`.
8.  **Return to Cubit**: The Model goes back through the layers, arriving at the Cubit wrapped in a `Right` (Success).
9.  **State Emission**: Cubit emits `PrayerTimesLoaded(prayerTimes)`.
10. **UI Update**: `home_screen.dart` rebuilds to show the prayer times.

## 🎯 Benefits Observed in this Project
*   **Testability**: You can easily unit test the `PrayerTimesCubit` by mocking the `GetPrayerTimesUseCase`.
*   **Maintainability**: If you decide to switch calculation libraries (e.g., from `adhan` to an online API), you **only** need to change the Data Source and Repository Impl. The Domain and Presentation layers remain utterly untouched.
*   **Scalability**: New features like Qibla or Quran can be seamlessly plugged into `features/` with their own independent layers without risking breaking the Home feature.
