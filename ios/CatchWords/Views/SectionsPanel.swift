import SwiftUI

/// "表示する項目と順番" — compact popover under the top-right button (SectionsPanel.tsx).
struct SectionsPanel: View {
    let prefs: CardPrefsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(L("表示する項目と順番"))
                    .scaledFont(size: 13, weight: .semibold)
                    .foregroundStyle(Theme.muted)
                    // Long in es / ko / vi: one line, a little smaller, next to the reset button.
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer()
                Button(L("既定に戻す")) {
                    Haptics.selection()
                    withAnimation(.snappy) { prefs.reset() }
                }
                .scaledFont(size: 13, weight: .semibold)
                .foregroundStyle(Theme.primaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            List {
                ForEach(prefs.order) { section in
                    row(section)
                        // Each item is its own card, so dragging the handle lifts a card off the stack.
                        .listRowBackground(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(prefs.isVisible(section) ? Theme.card : Theme.secondary.opacity(0.6))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
                                .padding(.horizontal, 8)
                        )
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 14))
                }
                .onMove { from, to in
                    Haptics.selection()
                    prefs.move(from: from, to: to)
                }
            }
            .listStyle(.plain)
            .listRowSpacing(6)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .frame(width: 300, height: 460)
    }

    private func row(_ section: CardSection) -> some View {
        let on = prefs.isVisible(section)
        return Button {
            Haptics.selection()
            withAnimation(.snappy) { prefs.setVisible(section, !on) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(on ? Theme.primary : Theme.muted.opacity(0.4), in: Circle())
                Text(section.title(for: prefs.target))
                    .scaledFont(size: 15, weight: on ? .semibold : .regular)
                    .foregroundStyle(on ? Theme.foreground : Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: on ? "eye" : "eye.slash")
                    .scaledFont(size: 14)
                    .foregroundStyle(on ? Theme.primaryInk : Theme.muted)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L("\(section.title(for: prefs.target))、\(on ? L("表示中") : L("非表示"))"))
        .accessibilityHint(L("タップで切り替え。並べ替えは右の取っ手を使います"))
    }
}
