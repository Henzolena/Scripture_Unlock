import SwiftUI
import SwiftData

/// Shown after all questions answered — verse of the day + streak update.
struct DismissedView: View {
    let alarm: Alarm
    @Query private var streaks: [StreakEntry]
    @Environment(\.modelContext) private var context
    @State private var showReadChapter = false
    @State private var votd:        VerseOfDay? = nil
    @State private var votdPlayer   = VersOfDayAudioPlayer()

    private var currentStreak: Int {
        var count = 0
        var date = Calendar.current.startOfDay(for: Date())
        let entries = streaks
        while entries.contains(where: { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.dismissedAt != nil }) {
            count += 1
            date = Calendar.current.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1E3A5F"), Color(hex: "2563EB")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(colors: [DesignSystem.pastoralGold.opacity(0.20), .clear],
                           center: .topTrailing, startRadius: 0, endRadius: 350)
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date().formatted(.dateTime.hour(.twoDigits(amPM: .wide)).minute(.twoDigits)))
                            .font(.system(size: 28, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white)
                        Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Good morning")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(2.5)
                        .textCase(.uppercase)
                        .foregroundStyle(DesignSystem.pastoralGold)
                    Text("You unlocked the day.")
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 12) {
                    Text("\u{201C}")
                        .font(DesignSystem.serif(80, italic: false))
                        .foregroundStyle(DesignSystem.pastoralGold)
                        .frame(height: 40)
                        .offset(y: 10)

                    Text(votd?.text ?? "O Lord, in the morning you hear my voice; in the morning I prepare a sacrifice for you and watch.")
                        .font(DesignSystem.serif(24, italic: true))
                        .foregroundStyle(.white.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        GoldRule(width: 18)
                        Text("\(votd?.ref ?? "Psalm 5:3") · \(votd?.translation ?? "NIV")")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignSystem.pastoralGold)
                        Spacer()
                        if let status = votd?.audioStatus, status != "failed" {
                            Button {
                                if status == "ready", let url = votd?.audioURL {
                                    if !votdPlayer.isPlaying { votdPlayer.load(url: url) }
                                    votdPlayer.togglePlayPause()
                                } else {
                                    votdPlayer.requestAndPlay { fresh in votd = fresh }
                                }
                            } label: {
                                if votdPlayer.isGenerating {
                                    HStack(spacing: 6) {
                                        ProgressView().scaleEffect(0.7).tint(DesignSystem.pastoralGold)
                                        Text("Generating…")
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(DesignSystem.pastoralGold)
                                    }
                                } else if status == "ready" {
                                    HStack(spacing: 6) {
                                        Image(systemName: votdPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.system(size: 20))
                                        Text(votdPlayer.isPlaying ? "Pause" : "Listen")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(DesignSystem.pastoralGold)
                                } else {
                                    HStack(spacing: 6) {
                                        Image(systemName: "play.circle")
                                            .font(.system(size: 20))
                                        Text("Generate audio")
                                            .font(.system(size: 12, weight: .semibold))
                                    }
                                    .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(votdPlayer.isGenerating)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .task {
                    votd = await VerseOfDayService.shared.today()
                    if let url = votd?.audioURL {
                        votdPlayer.load(url: url)
                    }
                }

                Spacer()

                if currentStreak > 0 {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(DesignSystem.pastoralGold.opacity(0.18))
                                .frame(width: 44, height: 44)
                            Image(systemName: "flame.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(DesignSystem.pastoralGold)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(currentStreak)-day streak")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(.white)
                            Text("One more morning in the Word.")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(.white.opacity(0.08))
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14), lineWidth: 0.5))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                HStack(spacing: 10) {
                    Button {
                        // Prayer prompt
                    } label: {
                        Label("Prayer", systemImage: "hands.and.sparkles.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 52)
                            .background(.white.opacity(0.12))
                            .cornerRadius(14)
                    }

                    Button {
                        showReadChapter = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Read the chapter")
                                .font(.system(size: 15, weight: .bold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(DesignSystem.deepBlue)
                        .frame(maxWidth: .infinity).frame(height: 52)
                        .background(.white)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .preferredColorScheme(.dark)
    }
}
