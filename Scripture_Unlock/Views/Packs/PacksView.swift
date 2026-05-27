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
                        activePack(pack).padding(.horizontal, 20).padding(.top, 16)
                    }

                    SectionHeader(title: "All packs").padding(.horizontal, 20).padding(.top, 26)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(VersePack.all) { pack in
                            PackCard(pack: pack, isActive: pack.id == profile?.activePackId) {
                                profile?.activePackId = pack.id
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 12)

                    Spacer(minLength: 32)
                }
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Verse Packs")
        }
    }

    private func activePack(_ pack: VersePack) -> some View {
        ZStack {
            DesignSystem.deepBlueGradient
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white.opacity(0.15)).frame(width: 40, height: 40)
                        Image(systemName: pack.iconName).foregroundStyle(DesignSystem.pastoralGold)
                    }
                    VStack(alignment: .leading) {
                        Text("Active pack").font(.system(size: 10, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.pastoralGold)
                        Text(pack.name).font(.system(size: 17, weight: .bold)).foregroundStyle(.white)
                    }
                    Spacer()
                    Text("\(pack.questionCount) verses").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                }
                ProgressView(value: 0.34)
                    .tint(DesignSystem.pastoralGold)
                    .background(.white.opacity(0.15))
                    .cornerRadius(2)
                HStack {
                    Text("142 learned").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("270 to go").font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(20)
        }
        .cornerRadius(20)
    }
}

struct PackCard: View {
    let pack: VersePack; let isActive: Bool; let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(Color(hex: pack.colorHex)).frame(width: 36, height: 36)
                    Image(systemName: pack.iconName).foregroundStyle(.white).font(.system(size: 16))
                }
                Text(pack.name).font(.system(size: 14, weight: .bold)).foregroundStyle(DesignSystem.ink)
                Text("\(pack.questionCount) verses").font(.system(size: 11)).foregroundStyle(DesignSystem.slate600)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignSystem.surface)
            .cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? Color(hex: pack.colorHex) : Color.clear, lineWidth: 2))
            .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Standalone picker (used from SetAlarmView nav link)

struct PackPickerView: View {
    @Binding var selectedPackId: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(VersePack.all) { pack in
            Button {
                selectedPackId = pack.id; dismiss()
            } label: {
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color(hex: pack.colorHex)).frame(width: 32, height: 32)
                        Image(systemName: pack.iconName).foregroundStyle(.white).font(.system(size: 14))
                    }
                    VStack(alignment: .leading) {
                        Text(pack.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(DesignSystem.ink)
                        Text(pack.description).font(.system(size: 12)).foregroundStyle(DesignSystem.slate600)
                    }
                    Spacer()
                    if pack.id == selectedPackId {
                        Image(systemName: "checkmark").foregroundStyle(DesignSystem.royalBlue).fontWeight(.bold)
                    }
                }
            }
        }
        .navigationTitle("Choose a pack")
    }
}
