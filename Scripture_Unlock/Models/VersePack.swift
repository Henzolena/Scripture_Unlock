import Foundation

/// A verse pack — groups questions by book/theme.
struct VersePack: Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let iconName: String      // SF Symbol name
    let colorHex: String
    let questionCount: Int

    // MARK: - Catalog

    static let beginner  = VersePack(id: "beginner",  name: "Beginner",         description: "Most-loved verses for new readers.",      iconName: "sun.max.fill",            colorHex: "059669", questionCount: 120)
    static let psalms    = VersePack(id: "psalms",    name: "Psalms",            description: "The morning prayer book of the Church.",  iconName: "hands.and.sparkles.fill", colorHex: "2563EB", questionCount: 412)
    static let proverbs  = VersePack(id: "proverbs",  name: "Proverbs",          description: "Wisdom for every morning.",               iconName: "book.fill",               colorHex: "C9A961", questionCount: 198)
    static let gospels   = VersePack(id: "gospels",   name: "Gospels",           description: "Stories and sayings of Jesus.",           iconName: "cross.fill",              colorHex: "1E3A5F", questionCount: 540)
    static let epistles  = VersePack(id: "epistles",  name: "Paul's Epistles",   description: "Doctrine, courage, the early Church.",    iconName: "envelope.fill",           colorHex: "7C3AED", questionCount: 320)
    static let ot        = VersePack(id: "ot",        name: "Old Testament",     description: "The full sweep of God's story.",          iconName: "flame.fill",              colorHex: "92400E", questionCount: 880)

    static let all: [VersePack] = [.beginner, .psalms, .proverbs, .gospels, .epistles, .ot]

    static func find(_ id: String) -> VersePack {
        all.first { $0.id == id } ?? .psalms
    }
}
