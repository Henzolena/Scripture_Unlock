import SwiftUI

/// Central design tokens for Scripture Unlock.
/// Mirrors the EECC Austin design system (colors_and_type.css).
enum DesignSystem {

    // MARK: - Colors
    static let deepBlue     = Color(hex: "1E3A5F")
    static let royalBlue    = Color(hex: "2563EB")
    static let pastoralGold = Color(hex: "C9A961")
    static let warmCream    = Color(hex: "FAF7F2")
    static let bethanyGreen = Color(hex: "059669")
    static let ink          = Color(hex: "0B1220")
    static let slate400     = Color(hex: "94A3B8")
    static let slate600     = Color(hex: "475569")
    static let slate700     = Color(hex: "334155")
    static let danger       = Color(hex: "DC2626")
    static let warning      = Color(hex: "D97706")
    static let surface      = Color(hex: "FFFFFF")

    // MARK: - Typography
    static let serifFont: Font = .custom("Georgia", size: 17)
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        italic ? .custom("Georgia-Italic", size: size) : .custom("Georgia", size: size)
    }

    // MARK: - Shadows
    static let shadow1 = Color.black.opacity(0.06)

    // MARK: - Gradients
    static let goldGradient = LinearGradient(
        colors: [Color(hex: "E5C684"), Color(hex: "C9A961")],
        startPoint: .top, endPoint: .bottom
    )
    static let deepBlueGradient = LinearGradient(
        colors: [Color(hex: "1E3A5F"), Color(hex: "2563EB")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let midnightGradient = RadialGradient(
        colors: [Color(hex: "1E3A5F"), Color(hex: "0F172A")],
        center: .init(x: 0.5, y: 0.3), startRadius: 0, endRadius: 500
    )
}

// MARK: - Color(hex:) initialiser

extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >>  8) & 0xFF) / 255
        let b = Double( int        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Shared view modifiers

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DesignSystem.surface)
            .cornerRadius(16)
            .shadow(color: DesignSystem.shadow1, radius: 8, x: 0, y: 2)
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardStyle()) }
}

// MARK: - GoldRule

struct GoldRule: View {
    var width: CGFloat = 18
    var body: some View {
        Rectangle()
            .fill(DesignSystem.pastoralGold)
            .frame(width: width, height: 2)
            .cornerRadius(1)
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var body: some View {
        HStack(spacing: 8) {
            GoldRule()
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(DesignSystem.slate600)
        }
    }
}

// MARK: - GoldSeal

struct GoldSeal: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "F0D898"), Color(hex: "C9A961"), Color(hex: "9C7E3B")],
                        center: .init(x: 0.35, y: 0.3),
                        startRadius: 0, endRadius: size * 0.6
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

            Image(systemName: "cross.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size * 0.44, height: size * 0.44)
                .foregroundStyle(DesignSystem.deepBlue)
        }
    }
}

// MARK: - PrimaryButton

struct PrimaryButton: View {
    let title: String
    var icon: String? = nil
    var style: ButtonStyleKind = .deepBlue
    let action: () -> Void

    enum ButtonStyleKind { case deepBlue, gold }

    var bg: AnyShapeStyle {
        switch style {
        case .deepBlue: return AnyShapeStyle(DesignSystem.deepBlue)
        case .gold:     return AnyShapeStyle(DesignSystem.goldGradient)
        }
    }

    var fg: Color { style == .gold ? DesignSystem.deepBlue : .white }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 17, weight: .bold))
                if let icon { Image(systemName: icon) }
            }
            .foregroundStyle(fg)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(bg)
            .cornerRadius(14)
            .shadow(color: style == .gold
                ? DesignSystem.pastoralGold.opacity(0.35)
                : DesignSystem.deepBlue.opacity(0.22),
                    radius: 8, x: 0, y: 4)
        }
    }
}

// MARK: - VerseCard

struct VerseCard: View {
    let reference: String
    let text: String
    let translation: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                GoldSeal(size: 20)
                Text("Verse for today")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(2.5)
                    .foregroundStyle(DesignSystem.pastoralGold)
                    .textCase(.uppercase)
            }

            Text("\u{201C}\(text)\u{201D}")
                .font(DesignSystem.serif(17, italic: true))
                .foregroundStyle(DesignSystem.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(reference) · \(translation)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.royalBlue)
        }
        .padding(18)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.goldGradient)
                .frame(height: 3)
        }
        .cardStyle()
    }
}

// MARK: - TriviaProgressBar

struct TriviaProgressBar: View {
    let total: Int
    let completed: Int
    let ringing: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(0..<total, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i < completed ? DesignSystem.pastoralGold
                              : i == completed ? DesignSystem.deepBlue
                              : Color.black.opacity(0.10))
                        .frame(height: 4)
                }
            }
            if ringing {
                HStack(spacing: 5) {
                    Circle()
                        .fill(DesignSystem.danger)
                        .frame(width: 6, height: 6)
                    Text("Ringing")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.danger)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(DesignSystem.danger.opacity(0.08))
                .cornerRadius(999)
                .overlay(RoundedRectangle(cornerRadius: 999).stroke(DesignSystem.danger.opacity(0.2), lineWidth: 0.5))
            }
        }
    }
}
