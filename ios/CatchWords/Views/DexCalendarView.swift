import SwiftUI

/// Month calendar with photo days; tapping a day swaps to that day's timeline (swipe right returns).
struct DexCalendarView: View {
    @Environment(DexStore.self) private var dex
    let stickers: [Sticker]
    @Binding var selectedDay: Date?
    let onOpen: (Sticker) -> Void
    /// When set, tapping a day hands it back instead of opening the in-sheet timeline (used by the map).
    var onPickDay: ((Date) -> Void)? = nil

    @State private var month: Date = Calendar(identifier: .gregorian).date(
        from: Calendar(identifier: .gregorian).dateComponents([.year, .month], from: Date())) ?? Date()
    @State private var timelineDay: Date?

    /// Gregorian whatever the iPhone's calendar (the grid's month names and weekday headers are Gregorian ones).
    private let cal = Calendar(identifier: .gregorian)
    private var weekdays: [String] { JPDate.veryShortWeekdays }

    var body: some View {
        Group {
            if let day = timelineDay {
                timeline(day)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                monthGrid
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.88), value: timelineDay)
        .onAppear {
            // Open on the month of the day already chosen (the map's day can be months back).
            if let d = selectedDay, let m = cal.date(from: cal.dateComponents([.year, .month], from: d)) { month = m }
        }
    }

    private var monthGrid: some View {
        let monthItems = stickers.filter { cal.isDate($0.takenAt, equalTo: month, toGranularity: .month) }
        let dayCount = Set(monthItems.map { cal.startOfDay(for: $0.takenAt) }).count
        return VStack(spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(JPDate.year(month))
                        .scaledFont(size: 12).foregroundStyle(Theme.muted)
                    Text(JPDate.month(month))
                        .scaledFont(size: 26, weight: .bold).foregroundStyle(Theme.primaryInk)
                    Text(L("\(monthItems.count)枚・\(dayCount)日"))
                        .scaledFont(size: 12, weight: .semibold, monospacedDigit: true)
                        .foregroundStyle(Theme.primaryInk)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Theme.primary.opacity(0.12), in: Capsule())
                        .padding(.top, 4)
                }
                Spacer()
                navCircle("chevron.left") { shift(-1) }.accessibilityLabel(L("前の月"))
                navCircle("chevron.right") { shift(1) }.accessibilityLabel(L("次の月"))
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { i, w in
                    Text(w).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(i == 0 ? Color(hex: 0xE5484D) : i == 6 ? Theme.primary : Theme.muted)
                }
                ForEach(Array(days().enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.aspectRatio(0.8, contentMode: .fit)
                    }
                }
            }
        }
        .padding(4)
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width < -40 { shift(1) } else if v.translation.width > 40 { shift(-1) }
        })
    }

    private func dayCell(_ day: Date) -> some View {
        let items = stickers.filter { cal.isDate($0.takenAt, inSameDayAs: day) }
        let first = items.first
        let isToday = cal.isDateInToday(day)
        let weekday = cal.component(.weekday, from: day)
        let isSelected = selectedDay.map { cal.isDate($0, inSameDayAs: day) } ?? false
        return Button {
            guard !items.isEmpty else { return }
            Haptics.selection()
            if let onPickDay { onPickDay(cal.startOfDay(for: day)) } else { timelineDay = day }
        } label: {
            Color(light: 0xE8F1FD, dark: 0x17233A)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay {
                    if let first {
                        DexThumb(sticker: first, inset: 3).allowsHitTesting(false)
                    }
                }
                .clipShape(.rect(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(first == nil ? .clear : Theme.primary, lineWidth: isSelected ? 3.5 : 2)
                )
                .overlay(alignment: first == nil ? .center : .bottomLeading) {
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: first == nil ? 13 : 12, weight: .bold)).monospacedDigit()
                        .foregroundStyle(first != nil ? .white : weekday == 1 ? Color(hex: 0xE5484D) : weekday == 7 ? Theme.primary : Theme.muted)
                        .shadow(color: first != nil ? .black.opacity(0.6) : .clear, radius: 2)
                        .padding(first == nil ? 0 : 5)
                }
                .overlay(alignment: .topTrailing) {
                    if items.count > 1 {
                        Text("\(items.count)")
                            .font(.system(size: 10, weight: .bold)).monospacedDigit()
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Theme.primary, in: Circle())
                            .overlay(Circle().stroke(.white, lineWidth: 1.5))
                            .padding(3)
                    }
                }
                .overlay(alignment: .top) {
                    if isToday && first == nil {
                        Circle().fill(Theme.primary).frame(width: 5, height: 5).padding(.top, 6)
                    }
                }
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(items.isEmpty)
    }

    private func timeline(_ day: Date) -> some View {
        let items = stickers.filter { cal.isDate($0.takenAt, inSameDayAs: day) }.sorted { $0.takenAt < $1.takenAt }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { timelineDay = nil } label: {
                    Label(L("月に戻る"), systemImage: "chevron.left").scaledFont(size: 14, weight: .semibold)
                }
                .foregroundStyle(Theme.primary)
                .frame(minHeight: 44)
                Spacer()
                Text(JPDate.monthDayWeek(day))
                    .scaledFont(size: 18).foregroundStyle(Theme.foreground)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, s in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Text(JPDate.time(s.takenAt))
                            .font(AppFont.mono(12, weight: .semibold)).foregroundStyle(Theme.muted)
                        Rectangle().fill(Theme.border).frame(width: 1).frame(maxHeight: .infinity)
                    }
                    .frame(width: 48)
                    Button { onOpen(s) } label: {
                        HStack(spacing: 12) {
                            Color.clear.frame(width: 72, height: 72)
                                .overlay {
                                    DexThumb(sticker: s).allowsHitTesting(false)
                                }
                                .background(Theme.surface2.opacity(0.5))
                                .clipShape(.rect(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(s.word?.headword ?? "").scaledFont(size: 20, weight: .bold).foregroundStyle(Theme.foreground)
                                    .lineLimit(1).minimumScaleFactor(0.45)
                                Text(s.word?.meaningJa ?? "").scaledFont(size: 13).foregroundStyle(Theme.muted)
                                    .lineLimit(2)
                                if s.lat != nil || !(s.locationName ?? "").isEmpty {
                                    Label {
                                        LocalizedPlaceText(lat: s.lat, lng: s.lng, saved: s.locationName, custom: s.locationCustom ?? false)
                                    } icon: {
                                        Image(systemName: "mappin")
                                    }
                                    .scaledFont(size: 11).foregroundStyle(Theme.muted)
                                }
                                if let cap = s.caption, !cap.isEmpty {
                                    Text(cap).scaledFont(size: 14).foregroundStyle(Theme.foreground.opacity(0.8)).lineLimit(2)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(10)
                        .background(Theme.card, in: .rect(cornerRadius: 18))
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.bottom, 12)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.spring(response: 0.5, dampingFraction: 0.85).delay(Double(idx) * 0.05), value: timelineDay)
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 60 { timelineDay = nil }
        })
    }

    private func navCircle(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.foreground)
                .frame(width: 44, height: 44)
                .background(Theme.secondary, in: Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
    }

    private func shift(_ delta: Int) {
        Haptics.selection()
        withAnimation(.snappy) { month = cal.date(byAdding: .month, value: delta, to: month) ?? month }
    }

    private func days() -> [Date?] {
        guard let range = cal.range(of: .day, in: .month, for: month) else { return [] }
        let firstWeekday = cal.component(.weekday, from: month) - 1
        var out: [Date?] = Array(repeating: nil, count: firstWeekday)
        for d in range {
            out.append(cal.date(byAdding: .day, value: d - 1, to: month))
        }
        return out
    }
}
