import SwiftUI

/// First-launch onboarding walkthrough explaining the scan → catalog → build loop.
/// Shows once and stores completion in UserDefaults.
struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "camera.viewfinder",
            title: "Scan Your Bricks",
            description: "Spread out your LEGO pieces and take a photo. \(AppConfig.appName) identifies every piece using on-device AI — no internet needed.",
            color: .legoRed
        ),
        OnboardingPage(
            icon: "cube.fill",
            title: "Know What You Have",
            description: "See a full inventory of your pieces organized by type, color, and size. Edit, add, or remove pieces anytime.",
            color: .legoBlue
        ),
        OnboardingPage(
            icon: "hammer.fill",
            title: "Discover What to Build",
            description: "Get build suggestions matched to your pieces with step-by-step instructions. Find missing pieces highlighted in your pile.",
            color: .legoGreen
        ),
        OnboardingPage(
            icon: "sparkles",
            title: "Powered by AI",
            description: "All scanning runs on-device using Core ML for instant, private results. No internet required.",
            color: .legoYellow
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    pageView(page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)

            // Bottom controls
            VStack(spacing: 20) {
                // Page indicators
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.legoBlue : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }

                // Action button
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation { currentPage += 1 }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    Text(currentPage < pages.count - 1 ? "Next" : "Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Skip button
                if currentPage < pages.count - 1 {
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: page.icon)
                .font(.system(size: 72))
                .foregroundStyle(page.color)
                .padding(.bottom, 8)

            Text(page.title)
                .font(.title)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            Text(page.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Spacer()
        }
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        UserDefaults.standard.set(true, forKey: UserDefaultsKey.hasCompletedOnboarding)
    }
}

private struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let color: Color
}
