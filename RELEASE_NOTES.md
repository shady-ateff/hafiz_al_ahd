# Hafiz Al-Ahd - Release Notes

## Version 1.1.0 (Major Update & Enhancements)

In this update, the app has been completely overhauled to deliver a faster and more stable experience:

🕌 **New Adhan Experience:** A beautifully redesigned, interactive Adhan screen featuring a smooth swipe-to-stop gesture.

⚡ **Optimized Performance:** Significant improvements in overall speed along with noticeably reduced battery consumption.

⚙️ **Smart Notifications:** Resolved overlapping notification issues using an intelligent background scheduling system.

⏱️ **Auto-Close Timer:** Introduced a smart auto-close feature for the Adhan screen to conserve battery and screen life.

---

## Version 1.0.0 (Initial Beta Release)

Welcome to the beta release of **Hafiz Al-Ahd**! This update brings essential features for prayer times, notifications, Azkar, and cross-platform usability. 

### 🎉 New Features

* **Prayer Times & Qibla Direction**: Get accurate, real-time prayer calculations worldwide. Integrates Qibla direction capabilities directly into the app.
* **Smart Prayer Notifications**: 
  * Full support for Adhan and Iqama alerts across devices.
  * Custom Fajr prayer sounds enabled for Android devices to distinguish the early morning call.
* **Azkar & Supplications Library**: Read daily morning, evening, and various other authentic Azkar easily with a streamlined reading tracker.
* **Offline Caching**: Most functionalities, including Azkar and previously loaded prayer times, remain accessible without an active internet connection.
* **Manual Location Selection**: Users can now manually search and pick their preferred location for prayer calculations when automatic GPS localization is unavailable or undesired.
* **Multi-Platform Support**: Enjoy a synchronized experience across Android, iOS, and Windows.
  * *Windows-Specific Additions*: System tray support, auto-launch at startup, and window state management.

### 🛠 Improvements & Fixes

* Resolved invalid constant value errors in the core `azkar_data` definitions.
* Refactored `PrayerTimesCubit` to optimize performance and prevent duplicate/stuck background notifications.
* Redesigned user interface utilizing elegant Arabic typography (Thuluth and Kufi fonts). 
* Implemented proper permission handling (Location, Notifications, Wake Lock) avoiding runtime crashes on newer Android/iOS versions.

---

### Known Issues & Upcoming Features
* The team is actively looking into expanding translation support and more audio recitations for Azkar.
* Continuous optimizations to background alarm handling on highly-restricted Android skins.

Thank you for choosing Hafiz Al-Ahd. We welcome your feedback!
