import SwiftUI
import SwiftData

struct PacksView: View {
    @Query private var profiles: [UserProfile]
    @Environment(\.modelContext) private var context

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let profile {
                        let pack = VersePack.find(profile.activePackId)
                        activePack(pack)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    SectionHeader(title: "All packs")
                        .padding(.horizontal, 20)
                        .padding(.top, 26)

                    LazyVGrid(
                        columns: [GridItem(.flexible()), GridItem(.flexible())],
                        spacing: 12
                    ) {
                        ForEach(VersePack.all) { pack in
                            PackCard(
                                pack: pack,
                                isActive: pack.id == profile?.activePackId
                            ) {
                                profile?.activePackId = pack.id
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                    Spacer(minLength: 32)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Verse Packs")
        }
    }

    // MARK: - Active pack hero card

    private func activePack(_ pack: VersePack) -> some View {
        ZStack(alignment: .bottomLeading) {
            // Background
            LinearGradient(
                colors: [Color(hex: "0D1B3E"), Color(hex: "1E3A5F")],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [DesignSystem.pastoralGold.opacity(0.20), .clear],
                center: .topTrailing, startRadius: 0, endRadius: 260
            )

            VStack(alignment: .leading, spacing: 14) {
                // Pack icon + label
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.14))
                            .frame(width: 44, height: 44)
                        Image(systemName: pack.iconName)
                            .foregroundStyle(DesignSystem.pastoralGold)
                            .font(.system(size: 20))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active pack")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(DesignSystem.pastoralGold)
                        Text(pack.name)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    // Verse count badge
                    Text("\(pack.questionCount) verses")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(.white.opacity(0.10))
                        .cornerRadius(8)
                }

                // Progress bar
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: 0.34)
                        .tint(DesignSystem.pastoralGold)
                        .background(.white.opacity(0.12))
                        .cornerRadius(2)
                    HStack {
                        Text("142 learned")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                        Spacer()
                        Text("270 remaining")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
            }
            .padding(20)
        }
        .cornerRadius(20)
        .shadow(color: Color(hex: "0D1B3E").opacity(0.30), radius: 12, x: 0, y: 6)
    }
}

// MARK: - Pack card

struct PackCard: View {
    let pack: VersePack
    let isActive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(hex: pack.colorHex))
                            .frame(width: 40, height: 40)
                        Image(systemName: pack.iconName)
                            .foregroundStyle(.white)
                            .font(.system(size: 18))
                    }
                    Spacer()
                    if isActive {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Color(hex: pack.colorHex))
                    }
                }
                Text(pack.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                Text(pack.description)
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.slate600)
                    .lineLimit(2)
                Text("\(pack.questionCount) verses")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color(hex: pack.colorHex))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.surface)
            .cornerRadius(14)
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isActive ? Color(hex: pack.colorHex).opacity(0.6) : Color.clear, lineWidth: 1.5)
            )
            .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standalone picker

struct PackPickerView: View {
    @Binding var selectedPackId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(VersePack.all) { pack in
            Button {
                selectedPackId = pack.id
                dismiss()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: pack.colorHex))
                            .frame(width: 32, height: 32)
                        Image(systemName: pack.iconName)
                            .foregroundStyle(.white)
                            .font(.system(size: 14))
                    }
                    VStack(alignment: .leading) {
                        Text(pack.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignSystem.ink)
                        Text(pack.description)
                            .font(.system(size: 12))
                            .foregroundStyle(DesignSystem.slate600)
                    }
                    Spacer()
                    if pack.id == selectedPackId {
                        Image(systemName: "checkmark")
                            .foregroundStyle(DesignSystem.royalBlue)
                            .fontWeight(.bold)
                    }
                }
            }
        }
        .navigationTitle("Choose a pack")
    }
}
