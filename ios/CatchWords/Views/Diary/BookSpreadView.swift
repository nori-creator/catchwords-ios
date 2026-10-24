import SwiftUI

/// The home album as a book, on a wide screen (the regular width class: iPhone Duo's inner display; owner 2026-10-24
/// 「左側を切り抜きステッカーのページにして右側は日記のようにして、ページめくれるようにする」). One day a spread: the left page is
/// the day's paper exactly as the iPhone shows it (`CollageBoard`, its placements unchanged — a page was always one
/// day's board), the right page its diary (`DiaryPageView`), the spine between them where the fold is. A horizontal
/// swipe, or the arrows under the spread, turns the whole spread to the day before or after (the book's order: older
/// days are earlier pages, today the last). The iPhone's home (compact width) is not this: it keeps its one vertical
/// scroll, with 「日記」 on each day opening the right page as a sheet.
struct BookSpreadView: View {
    /// Newest first, today leading (`AlbumDay.days`).
    let days: [AlbumDay]
    let onOpen: (Sticker) -> Void
    let onCamera: () -> Void
    var onEditingChange: ((Bool) -> Void)? = nil
    var finishRequest: Int = 0
    /// A day picked in the calendar: the spread turns to it when `jumpCount` changes.
    var jumpDay: Date? = nil
    var jumpCount: Int = 0

    /// Which spread shows: 0 = today.
    @State private var index = 0
    /// The last turn's direction, for the page-turn transition: +1 = towards today, −1 = back in time.
    @State private var direction = 1
    @Environment(\.appReduceMotion) private var reduceMotion

    /// The spine's width (the fold's region on a folded phone).
    static let spineWidth: CGFloat = 28
    private static let ink = Color(hex: 0x33291F)

    private var current: AlbumDay? { days.indices.contains(index) ? days[index] : nil }

    var body: some View {
        VStack(spacing: 14) {
            if let day = current {
                spread(day)
                    .id(day.id)
                    .transition(turnTransition)
            }
            pager
        }
        .animation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.86), value: index)
        .onChange(of: days.count) { _, _ in index = min(index, max(0, days.count - 1)) }
        .onChange(of: jumpCount) { _, _ in
            guard let d = jumpDay, let i = days.firstIndex(where: { Calendar.current.isDate($0.day, inSameDayAs: d) }) else { return }
            turn(to: i)
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 40)
                .onEnded { v in
                    let w = v.translation.width, h = v.translation.height
                    guard abs(w) > abs(h) * 2 else { return }
                    // Dragging right pulls the earlier page over (back in time); left turns towards today.
                    if w > 0 { turn(to: index + 1) } else { turn(to: index - 1) }
                }
        )
        .accessibilityElement(children: .contain)
    }

    private func turn(to i: Int) {
        guard days.indices.contains(i), i != index else { return }
        direction = i < index ? 1 : -1
        Haptics.selection()
        SoundService.shared.pon(open: true)
        index = i
    }

    /// The whole spread turns about the spine (a 3D rotation about its middle); just a fade with reduced motion.
    private var turnTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let a: Double = direction > 0 ? 70 : -70
        return .asymmetric(
            insertion: .modifier(active: PageTurn(angle: -a), identity: PageTurn(angle: 0)).combined(with: .opacity),
            removal: .modifier(active: PageTurn(angle: a), identity: PageTurn(angle: 0)).combined(with: .opacity)
        )
    }

    // MARK: The spread

    private func spread(_ d: AlbumDay) -> some View {
        HStack(alignment: .top, spacing: 0) {
            leftPage(d)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .tourAnchor(.album, if: index == 0)
            spine
            DiaryPageView(day: d.day)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    /// 10月24日(金); a day of another year says its year too.
    private static func title(_ day: Date) -> String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: day) == cal.component(.year, from: Date())
        return sameYear ? JPDate.monthDayWeek(day) : JPDate.yearMonthDayWeek(day)
    }

    /// The day's paper, as on the iPhone's home: its date, its count, its board.
    private func leftPage(_ d: AlbumDay) -> some View {
        let isToday = Calendar.current.isDateInToday(d.day)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(Self.title(d.day))
                    .scaledFont(size: 26, weight: .heavy)
                    .foregroundStyle(Self.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !d.items.isEmpty {
                    Text(L("\(d.items.count)語"))
                        .font(AppFont.mono(14, weight: .semibold))
                        .foregroundStyle(Self.ink.opacity(0.5))
                }
            }
            .padding(.horizontal, 10)
            if d.items.isEmpty {
                VStack(spacing: 14) {
                    if isToday {
                        Button(action: onCamera) {
                            Label(L("今日の1枚を撮る"), systemImage: "camera.fill")
                                .scaledFont(size: 15, weight: .semibold)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 20)
                                .frame(minHeight: 46)
                                .background(Theme.primary, in: Capsule())
                                .shadow(color: Theme.primary.opacity(0.35), radius: 10, y: 5)
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                CollageBoard(items: d.items, editable: true, onOpen: onOpen, onEditingChange: onEditingChange,
                             finishRequest: finishRequest)
            }
        }
    }

    /// The spine: the paper dips into the binding — a soft shadow on both pages, darkest at the middle.
    private var spine: some View {
        LinearGradient(
            colors: [.clear, Self.ink.opacity(0.05), Self.ink.opacity(0.14), Self.ink.opacity(0.05), .clear],
            startPoint: .leading, endPoint: .trailing
        )
        .frame(width: Self.spineWidth)
        .frame(maxHeight: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: Turning the pages

    private var pager: some View {
        HStack(spacing: 18) {
            Button { turn(to: index + 1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Self.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(index + 1 >= days.count)
            .accessibilityLabel(L("前の日"))
            .accessibilityIdentifier("spread.older")
            Text(current.map { Calendar.current.isDateInToday($0.day) ? L("今日") : Self.title($0.day) } ?? "")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(Self.ink.opacity(0.6))
                .frame(minWidth: 120)
            Button { turn(to: index - 1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(Self.ink.opacity(0.07), in: Circle())
            }
            .buttonStyle(PressableStyle(scale: 0.92))
            .disabled(index == 0)
            .accessibilityLabel(L("次の日"))
            .accessibilityIdentifier("spread.newer")
        }
        .foregroundStyle(Self.ink)
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

/// A page turning about the spine: the spread rotates about its own vertical middle, with a little perspective.
private struct PageTurn: ViewModifier {
    let angle: Double

    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
    }
}

/// A day whose diary is open as a sheet (the iPhone's home).
struct DiaryDay: Identifiable, Equatable {
    let day: Date
    var id: Date { day }
}
