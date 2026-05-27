import SwiftUI
import SwiftData

/// Full-screen celebration modal shown after each correct answer.
/// Auto-dismisses after 3 s; tap anywhere to continue immediately.
/// The alarm tone keeps ringing behind it — the user cannot escape.
struct CorrectMomentView: View {

    let question: TriviaQuestion
    let completedStep: Int       // 0-based index just answered (0 = first Q)
    let totalSteps: Int
    let onContinue: () -> Void

    // MARK: - SwiftData + Amharic

    @Query private var profiles: [UserProfile]
    @State private var amharicText: String? = nil

    private var amharicEnabled: Bool {
        profiles.first?.amharicAlongside ?? false
    }

    // MARK: - Animation states

    @State private var sealScale: CGFloat   = 0.2
    @State private var sealOpacity: Double  = 0
    @State private var ringScale: CGFloat   = 0.4
    @State private var ringOpacity: Double  = 0

    @State private var badgeOffset: CGFloat = 18
    @State private var badgeOpacity: Double = 0

    @State private var verseOpacity: Double = 0
    @State private var themeOpacity: Double = 0
    @State private var focusOpacity: Double = 0
    @State private var hintOpacity:  Double = 0

    @State private var autoDismissTask: Task<Void, Never>?
    @State private var didDismiss = false

    // MARK: - Body

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Spacer()

                // ── Gold seal burst ─────────────────────────────────────────
                sealBurst
                    .padding(.bottom, 28)

                // ── "CORRECT" badge ─────────────────────────────────────────
                Text("CORRECT")
                    .font(.system(size: 12, weight: .black))
                    .tracking(4)
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .padding(.horizontal, 22).padding(.vertical, 9)
                    .background(DesignSystem.pastoralGold.opacity(0.15))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DesignSystem.pastoralGold.opacity(0.45), lineWidth: 1))
                    .offset(y: badgeOffset)
                    .opacity(badgeOpacity)

                // ── Verse ───────────────────────────────────────────────────
                verseBlock
                    .padding(.top, 28)
                    .opacity(verseOpacity)

                // ── Key phrase ──────────────────────────────────────────────
                keyPhrase
                    .padding(.top, 18)
                    .opacity(themeOpacity)

                // ── Morning focus ───────────────────────────────────────────
                morningFocus
                    .padding(.top, 22)
                    .opacity(focusOpacity)

                Spacer()

                // ── Progress dots + hint ─────────────────────────────────────
                bottomSection
                    .opacity(hintOpacity)
                    .padding(.bottom, 44)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
        .onAppear { runAnimations() }
        .onDisappear { autoDismissTask?.cancel() }
        .task {
            if amharicEnabled {
                amharicText = await BetezionService.shared.amharic(forRef: question.verseRef)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub-views

    private var background: some View {
        ZStack {
            Color(hex: "080E1C").ignoresSafeArea()
            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.13), .clear],
                center: .init(x: 0.5, y: 0.35),
                startRadius: 0, endRadius: 340
            )
            .ignoresSafeArea()
        }
    }

    private var sealBurst: some View {
        ZStack {
            // Outer pulsing ring
            Circle()
                .stroke(DesignSystem.pastoralGold.opacity(0.18), lineWidth: 1.5)
                .frame(width: 156, height: 156)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Mid ring
            Circle()
                .stroke(DesignSystem.pastoralGold.opacity(0.28), lineWidth: 1)
                .frame(width: 120, height: 120)
                .scaleEffect(ringScale)
                .opacity(ringOpacity)

            // Filled circle
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            DesignSystem.pastoralGold.opacity(0.30),
                            DesignSystem.pastoralGold.opacity(0.10)
                        ],
                        center: .center,
                        startRadius: 0, endRadius: 50
                    )
                )
                .frame(width: 96, height: 96)
                .scaleEffect(sealScale)
                .opacity(sealOpacity)

            // Checkmark
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(DesignSystem.pastoralGold)
                .scaleEffect(sealScale)
                .opacity(sealOpacity)
        }
    }

    private var verseBlock: some View {
        VStack(spacing: 10) {
            Text(question.verseRef.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2.5)
                .foregroundStyle(DesignSystem.pastoralGold)

            Text("\u{201C}\(question.verseText)\u{201D}")
                .font(DesignSystem.serif(15, italic: true))
                .foregroundStyle(.white.opacity(0.80))
                .multilineTextAlignment(.center)
                .lineLimit(5)
                .padding(.horizontal, 36)

            // Amharic translation (shown only when the setting is on + loaded)
            if amharicEnabled {
                Divider()
                    .background(.white.opacity(0.15))
                    .padding(.horizontal, 36)
                    .padding(.top, 4)

                HStack(spacing: 6) {
                    Text("🇪🇹")
                        .font(.system(size: 11))
                    Text("አማርኛ")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(DesignSystem.pastoralGold)
                }

                if let amharic = amharicText {
                    Text(amharic)
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.70))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 36)
                        .environment(\.layoutDirection, .leftToRight)
                } else {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white.opacity(0.5))
                        Text("በመጫን ላይ…")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.40))
                    }
                }
            }
        }
    }

    private var keyPhrase: some View {
        VStack(spacing: 10) {
            GoldRule(width: 20)

            HStack(spacing: 8) {
                Image(systemName: themeIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.pastoralGold.opacity(0.8))
                Text(themeLabel.uppercased())
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(DesignSystem.pastoralGold.opacity(0.8))
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(.white.opacity(0.06))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.10), lineWidth: 0.5))
        }
    }

    private var morningFocus: some View {
        VStack(spacing: 10) {
            Text("MORNING FOCUS")
                .font(.system(size: 9, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.35))

            Text(focusPrompt)
                .font(DesignSystem.serif(14, italic: true))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var bottomSection: some View {
        VStack(spacing: 14) {
            // Progress dots
            HStack(spacing: 7) {
                ForEach(0..<totalSteps, id: \.self) { i in
                    Capsule()
                        .fill(i <= completedStep
                              ? DesignSystem.pastoralGold
                              : Color.white.opacity(0.18))
                        .frame(width: i <= completedStep ? 22 : 7, height: 7)
                        .animation(.spring(duration: 0.3), value: completedStep)
                }
            }

            Text(completedStep + 1 < totalSteps
                 ? "\(totalSteps - completedStep - 1) question\(totalSteps - completedStep - 1 == 1 ? "" : "s") remaining · tap to continue"
                 : "Last one · tap to see your verse")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.30))
        }
    }

    // MARK: - Computed content

    private var themeIcon: String {
        let b = question.book.lowercased()
        if ["psalm","psalms"].contains(b)              { return "music.note" }
        if ["proverb","proverbs"].contains(b)          { return "lightbulb.fill" }
        if ["matthew","mark","luke","john"].contains(b){ return "cross.fill" }
        if ["romans","galatians","ephesians","philippians",
            "colossians","hebrews","james"].contains(b){ return "scroll.fill" }
        if ["genesis","exodus","deuteronomy","joshua"].contains(b){ return "flame.fill" }
        return VersePack.find(question.packId).iconName
    }

    private var themeLabel: String {
        let b = question.book.lowercased()
        if ["psalm","psalms"].contains(b)              { return "Praise & Prayer" }
        if ["proverb","proverbs"].contains(b)          { return "Wisdom" }
        if ["matthew","mark","luke","john"].contains(b){ return "Life of Christ" }
        if ["romans","galatians","ephesians","philippians",
            "colossians","hebrews","james"].contains(b){ return "Doctrine" }
        if ["genesis","exodus","deuteronomy","joshua"].contains(b){ return "Covenant History" }
        return VersePack.find(question.packId).name
    }

    private var focusPrompt: String {
        let b = question.book.lowercased()
        if ["psalm","psalms"].contains(b) {
            return "Let this shape your worship today. Return to this verse when your heart feels heavy."
        }
        if ["proverb","proverbs"].contains(b) {
            return "Apply this wisdom to one concrete decision before noon."
        }
        if ["matthew","mark","luke","john"].contains(b) {
            return "Jesus spoke or lived this truth. Walk with Him in it today."
        }
        if ["romans","galatians","ephesians","philippians"].contains(b) {
            return "Paul wrote this to anchor real believers in real trials. Let it anchor you."
        }
        if ["hebrews","james","peter","john"].contains(b) {
            return "Hold this word through the first challenge you face today."
        }
        if ["genesis","exodus","numbers","deuteronomy","joshua"].contains(b) {
            return "God was faithful then. He is faithful now. Trust the same God."
        }
        return "Carry this word out of your bedroom and into your day."
    }

    // MARK: - Animation & dismissal

    private func runAnimations() {
        // Rings
        withAnimation(.spring(response: 0.55, dampingFraction: 0.58).delay(0.05)) {
            ringScale   = 1
            ringOpacity = 1
        }
        // Seal
        withAnimation(.spring(response: 0.48, dampingFraction: 0.52).delay(0.12)) {
            sealScale   = 1
            sealOpacity = 1
        }
        // Badge slides up
        withAnimation(.spring(response: 0.42, dampingFraction: 0.65).delay(0.32)) {
            badgeOffset = 0
            badgeOpacity = 1
        }
        // Verse fades in
        withAnimation(.easeOut(duration: 0.45).delay(0.52)) {
            verseOpacity = 1
        }
        // Theme chip
        withAnimation(.easeOut(duration: 0.40).delay(0.72)) {
            themeOpacity = 1
        }
        // Focus prompt
        withAnimation(.easeOut(duration: 0.40).delay(0.90)) {
            focusOpacity = 1
        }
        // Bottom hint
        withAnimation(.easeOut(duration: 0.40).delay(1.10)) {
            hintOpacity = 1
        }

        // Auto-dismiss after 3 s
        autoDismissTask = Task {
            do {
                try await Task.sleep(for: .seconds(3))
                await MainActor.run { dismiss() }
            } catch {
                // Cancelled — user tapped manually
            }
        }
    }

    private func dismiss() {
        guard !didDismiss else { return }
        didDismiss = true
        autoDismissTask?.cancel()
        onContinue()
    }
}
