abstract class OnboardingState {}

class OnboardingInitial extends OnboardingState {}

class OnboardingPageChanged extends OnboardingState {
  final int page;
  OnboardingPageChanged(this.page);
}

class OnboardingComplete extends OnboardingState {}
