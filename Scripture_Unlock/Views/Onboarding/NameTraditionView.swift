import SwiftUI

struct NameTraditionView: View {
    let profile: UserProfile
    let onContinue: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    private let traditions = ["Evangelical","Orthodox","Catholic","Pentecostal","Mainline Protestant","Other"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                OnboardingDots(total: 5, current: 2)
                    .frame(maxWidth: .infinity).padding(.top, 16)

                Text("About you")
                    .font(.system(size: 11, weight: .bold)).tracking(2.5).textCase(.uppercase)
                    .foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 36)

                Text("What should we\ncall you?")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(DesignSystem.ink)
                    .padding(.top, 10)

                Text("Your name appears on the morning greeting and your streak.")
                    .font(.system(size: 14)).foregroundStyle(DesignSystem.slate600)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Name").font(.system(size: 11, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.slate600)
                    TextField("Your name", text: $name)
                        .font(.system(size: 18, weight: .medium))
                        .focused($focused)
                        .padding(.horizontal, 18).frame(height: 56)
                        .background(DesignSystem.surface)
                        .cornerRadius(14)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(focused ? DesignSystem.royalBlue : Color.black.opacity(0.1), lineWidth: focused ? 1.5 : 0.5))
                        .shadow(color: DesignSystem.shadow1, radius: 6, x: 0, y: 2)
                }
                .padding(.top, 28)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tradition (optional)").font(.system(size: 11, weight: .bold)).tracking(2).textCase(.uppercase).foregroundStyle(DesignSystem.slate600)
                    FlowLayout(spacing: 8) {
                        ForEach(traditions, id: \.self) { t in
                            let on = profile.denomination == t
                            Button {
                                profile.denomination = on ? "" : t
                            } label: {
                                Text(t)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(on ? .white : DesignSystem.ink)
                                    .padding(.horizontal, 16).padding(.vertical, 10)
                                    .background(on ? DesignSystem.deepBlue : DesignSystem.surface)
                                    .cornerRadius(999)
                                    .overlay(RoundedRectangle(cornerRadius: 999)
                                        .stroke(on ? Color.clear : Color.black.opacity(0.12), lineWidth: 0.5))
                                    .shadow(color: on ? DesignSystem.deepBlue.opacity(0.22) : .clear, radius: 6, x: 0, y: 3)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, 28)

                Spacer(minLength: 48)

                PrimaryButton(title: "Continue", icon: "chevron.right") {
                    profile.name = name.trimmingCharacters(in: .whitespaces)
                    onContinue()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .padding(.bottom, 48)
            }
            .padding(.horizontal, 24)
        }
        .background(DesignSystem.warmCream.ignoresSafeArea())
        .onAppear { focused = true }
    }
}

// MARK: - Flow layout for chips

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowH: CGFloat = 0; var maxY: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > width && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            rowH = max(rowH, s.height); x += s.width + spacing
            maxY = max(maxY, y + rowH)
        }
        return CGSize(width: width, height: maxY)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowH: CGFloat = 0
        for view in subviews {
            let s = view.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            rowH = max(rowH, s.height); x += s.width + spacing
        }
    }
}
