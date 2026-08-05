import SwiftUI

struct VerseNoteSheet: View {
    let verseRef: String
    let book: String
    let chapter: Int
    let verse: Int
    let verseText: String

    @Environment(\.dismiss) private var dismiss
    @State private var body_text = ""
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verseRef)
                            .font(.system(size: 13, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(DesignSystem.pastoralGold)
                        Text(verseText)
                            .font(DesignSystem.serif(16))
                            .foregroundStyle(DesignSystem.ink.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Your reflection")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1.5)
                            .textCase(.uppercase)
                            .foregroundStyle(DesignSystem.slate600)

                        TextEditor(text: $body_text)
                            .font(.system(size: 15))
                            .foregroundStyle(DesignSystem.ink)
                            .frame(minHeight: 200)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                    }
                    .padding(16)
                    .cardStyle()
                }
                .padding(20)
            }
            .background(DesignSystem.warmCream.ignoresSafeArea())
            .navigationTitle("Personal Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DesignSystem.slate600)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DesignSystem.royalBlue)
                        .disabled(isSaving)
                }
            }
        }
        .task {
            await VerseNoteService.shared.load(verseRef: verseRef)
            body_text = VerseNoteService.shared.note(for: verseRef)?.body ?? ""
        }
    }

    private func save() {
        isSaving = true
        Task {
            let trimmed = body_text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                await VerseNoteService.shared.delete(verseRef: verseRef)
                ToastService.shared.noteDeleted()
            } else {
                await VerseNoteService.shared.save(
                    verseRef: verseRef, book: book,
                    chapter: chapter, verse: verse, body: trimmed
                )
                ToastService.shared.noteSaved()
            }
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}
