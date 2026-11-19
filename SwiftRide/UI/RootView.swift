import SwiftUI

struct RootView: View {
    @AppStorage(Prefs.onboarded) private var onboarded = false

    var body: some View {
        Group {
            if onboarded {
                HomeView()
                    .transition(.opacity)
            } else {
                OnboardingView { withAnimation(.smooth) { onboarded = true } }
                    .transition(.opacity)
            }
        }
        .tint(Theme.accent)
    }
}
