import SwiftUI
import Charts
import MapKit

// The charts of the developer's 分析 (owner 2026-11-13: 「グラフやチャートで視覚的に見やすく…一から設計し直して」):
// a small line under a number, tiny bars in a row, the days used as a calendar, the hours used as a grid, a stacked
// bar, and a map of areas. Numbers only — nothing here shows a photo, a word or an exact place.

/// A small line of the last days, under a number (no axes).
struct AdminSparkline: View {
    let values: [Double]
    var color: Color = Theme.primary

    var body: some View {
        let points: [AdminPoint] = values.enumerated().map { AdminPoint(i: $0.offset, v: $0.element) }
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("i", p.i), y: .value("v", p.v))
                    .foregroundStyle(color.opacity(0.14))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("i", p.i), y: .value("v", p.v))
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("i", last.i), y: .value("v", last.v))
                    .foregroundStyle(color)
                    .symbolSize(18)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 26)
        .accessibilityHidden(true)
    }
}

struct AdminPoint: Identifiable {
    let i: Int
    let v: Double
    var id: Int { i }
}

/// Tiny bars for a row (the last 14 days): a day with nothing is a flat grey mark.
struct AdminMiniBars: View {
    let values: [Int]
    var height: CGFloat = 18

    var body: some View {
        let top: Int = max(1, values.max() ?? 1)
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(v > 0 ? Theme.primary : Theme.border)
                    .frame(width: 3, height: v > 0 ? max(3, height * CGFloat(v) / CGFloat(top)) : 2)
            }
        }
        .frame(height: height, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

/// The days used, as a calendar of weeks (columns, Monday first): the darker, the more caught and reviewed that day.
struct AdminActivityCalendar: View {
    /// Oldest first: "YYYY-MM-DD" and that day's catches + reviews.
    let days: [AdminDayValue]

    var body: some View {
        let columns: [[Int?]] = Self.columns(days)
        let top: Int = max(1, days.map(\.value).max() ?? 1)
        let names: [String] = Self.weekdayNames
        HStack(alignment: .top, spacing: 3) {
            VStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { r in
                    Text(r % 2 == 0 ? (names[safe: r] ?? "") : "")
                        .scaledFont(size: 9).foregroundStyle(Theme.muted)
                        .frame(width: 14, height: 12)
                }
            }
            ForEach(Array(columns.enumerated()), id: \.offset) { _, col in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { r in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(Self.shade(Self.cell(col, r), top: top))
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("使った日"))
    }

    static func cell(_ col: [Int?], _ r: Int) -> Int? {
        r < col.count ? col[r] : nil
    }

    static func shade(_ v: Int?, top: Int) -> Color {
        guard let v else { return Color.clear }
        if v <= 0 { return Theme.secondary }
        let level: Double = min(1, Double(v) / Double(top))
        return Theme.primary.opacity(0.25 + 0.75 * level)
    }

    /// Monday-first weekday names in the display language.
    static var weekdayNames: [String] {
        let sundayFirst: [String] = JPDate.veryShortWeekdays
        guard sundayFirst.count == 7 else { return Array(repeating: "", count: 7) }
        return Array(sundayFirst[1...]) + [sundayFirst[0]]
    }

    /// Weeks as columns of seven (Monday … Sunday); the days before the first and after the last are empty (nil).
    static func columns(_ days: [AdminDayValue]) -> [[Int?]] {
        guard let first = days.first else { return [] }
        var cells: [Int?] = Array(repeating: nil, count: mondayIndex(first.day))
        for d in days { cells.append(d.value) }
        while cells.count % 7 != 0 { cells.append(nil) }
        var out: [[Int?]] = []
        var i = 0
        while i < cells.count {
            out.append(Array(cells[i..<(i + 7)]))
            i += 7
        }
        return out
    }

    /// 0 = Monday … 6 = Sunday, for a Taipei day key.
    static func mondayIndex(_ key: String) -> Int {
        guard let d = SupabaseDate.parse("\(key)T12:00:00+08:00") else { return 0 }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return (cal.component(.weekday, from: d) + 5) % 7
    }
}

struct AdminDayValue: Identifiable, Equatable {
    let day: String
    let value: Int
    var id: String { day }
}

/// When the app is used: seven rows (Monday …) by eight three-hour blocks (Taipei time).
struct AdminHourGrid: View {
    /// 7 × 24 counts (Monday first, 0 … 23 o'clock).
    let grid: [[Int]]

    var body: some View {
        let blocks: [[Int]] = Self.blocks(grid)
        let top: Int = max(1, blocks.flatMap { $0 }.max() ?? 1)
        let names: [String] = AdminActivityCalendar.weekdayNames
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<7, id: \.self) { r in
                HStack(spacing: 3) {
                    Text(names[safe: r] ?? "").scaledFont(size: 10).foregroundStyle(Theme.muted).frame(width: 16)
                    ForEach(0..<8, id: \.self) { c in
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Self.shade(blocks[r][c], top: top))
                            .frame(maxWidth: .infinity)
                            .frame(height: 16)
                    }
                }
            }
            HStack(spacing: 3) {
                Color.clear.frame(width: 16, height: 1)
                ForEach(0..<8, id: \.self) { c in
                    Text("\(c * 3)").scaledFont(size: 9, monospacedDigit: true).foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("使う時間帯"))
    }

    static func shade(_ v: Int, top: Int) -> Color {
        v > 0 ? Theme.primary.opacity(0.18 + 0.82 * Double(v) / Double(top)) : Theme.secondary
    }

    /// 24 hours → 8 blocks of three (always 7 × 8).
    static func blocks(_ grid: [[Int]]) -> [[Int]] {
        (0..<7).map { r in
            let hours: [Int] = r < grid.count ? grid[r] : []
            return (0..<8).map { b in
                var sum = 0
                for h in (b * 3)..<(b * 3 + 3) where h < hours.count { sum += hours[h] }
                return sum
            }
        }
    }
}

/// One part of a stacked bar.
struct AdminPart: Identifiable {
    let label: String
    let value: Int
    let color: Color
    var id: String { label }
}

/// A stacked bar of parts (memory levels) with a legend under it.
struct AdminStackBar: View {
    let parts: [AdminPart]
    var height: CGFloat = 24

    var body: some View {
        let total: Int = max(1, parts.reduce(0) { $0 + $1.value })
        let shown: [AdminPart] = parts.filter { $0.value > 0 }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                let room: CGFloat = max(0, g.size.width - 2 * CGFloat(max(0, shown.count - 1)))
                HStack(spacing: 2) {
                    ForEach(shown) { p in
                        ZStack {
                            Rectangle().fill(p.color)
                            Text(AdminFormat.int(p.value))
                                .scaledFont(size: 10, weight: .bold, monospacedDigit: true)
                                .foregroundStyle(Color(hex: 0x10202E))
                                .lineLimit(1).minimumScaleFactor(0.5)
                        }
                        .frame(width: max(8, room * CGFloat(p.value) / CGFloat(total)))
                    }
                }
                .clipShape(.rect(cornerRadius: 6, style: .continuous))
            }
            .frame(height: height)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 4) {
                ForEach(parts) { p in
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 2).fill(p.color).frame(width: 9, height: 9)
                        Text(p.label).scaledFont(size: 11).foregroundStyle(Theme.muted).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One area on the map: a city and district and how many catches (never a street or a point someone stood on).
struct AdminAreaSpot: Identifiable, Equatable {
    let name: String
    let n: Int
    var id: String { name }
}

/// Where photos are taken, as circles per area (owner 2026-11-13: 「ユーザーがどこで取ったとかの位置が見えない」).
///
/// The server sends only area names (市と区, privacy policy §2: no exact position); this phone looks each name up
/// (`AdminAreaGeocoder`, Apple's place search) and puts a circle sized by the count at the area's middle.
struct AdminAreaMap: View {
    let spots: [AdminAreaSpot]
    var height: CGFloat = 210

    @State private var placed: [PlacedArea] = []
    @State private var looked = false
    @State private var position: MapCameraPosition = .automatic

    struct PlacedArea: Identifiable {
        let name: String
        let n: Int
        let coordinate: CLLocationCoordinate2D
        var id: String { name }
    }

    var body: some View {
        let top: Int = max(1, spots.map(\.n).max() ?? 1)
        ZStack {
            Map(position: $position) {
                ForEach(placed) { a in
                    Annotation(a.name, coordinate: a.coordinate, anchor: .center) {
                        Circle()
                            .fill(Theme.primary.opacity(0.26))
                            .overlay(Circle().stroke(Theme.primary, lineWidth: 1.5))
                            .overlay(
                                Text(AdminFormat.int(a.n))
                                    .scaledFont(size: 10, weight: .bold, monospacedDigit: true)
                                    .foregroundStyle(Theme.primaryInk)
                            )
                            .frame(width: Self.size(a.n, top), height: Self.size(a.n, top))
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            if !looked {
                ProgressView().tint(Theme.muted)
            } else if placed.isEmpty {
                Text(L("地図に置ける地名がありません"))
                    .scaledFont(size: 12).foregroundStyle(Theme.muted)
                    .padding(8)
                    .background(Theme.card.opacity(0.9), in: Capsule())
            }
        }
        .frame(height: height)
        .clipShape(.rect(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .task(id: spots.map(\.name).joined(separator: "|")) { await place() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L("撮った場所の地図"))
    }

    static func size(_ n: Int, _ top: Int) -> CGFloat {
        20 + 34 * CGFloat((Double(n) / Double(max(1, top))).squareRoot())
    }

    private func place() async {
        var found: [PlacedArea] = []
        for s in spots.prefix(12) {
            if let c = await AdminAreaGeocoder.shared.coordinate(for: s.name) {
                found.append(PlacedArea(name: s.name, n: s.n, coordinate: c))
            }
        }
        placed = found
        looked = true
        if let region = Self.region(found.map(\.coordinate)) { position = .region(region) }
    }

    /// The smallest region that holds every circle, with a margin.
    static func region(_ points: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard let first = points.first else { return nil }
        var minLat = first.latitude, maxLat = first.latitude, minLon = first.longitude, maxLon = first.longitude
        for p in points {
            minLat = min(minLat, p.latitude)
            maxLat = max(maxLat, p.latitude)
            minLon = min(minLon, p.longitude)
            maxLon = max(maxLon, p.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.04, (maxLat - minLat) * 1.6),
                                    longitudeDelta: max(0.04, (maxLon - minLon) * 1.6))
        return MKCoordinateRegion(center: center, span: span)
    }
}

/// Area names → the middle of the area, looked up once per name on this phone (Apple's place search).
final class AdminAreaGeocoder {
    static let shared = AdminAreaGeocoder()
    private var found: [String: CLLocationCoordinate2D] = [:]
    private var missing: Set<String> = []

    func coordinate(for name: String) async -> CLLocationCoordinate2D? {
        if let hit = found[name] { return hit }
        if missing.contains(name) { return nil }
        let marks: [CLPlacemark]? = try? await CLGeocoder().geocodeAddressString(name)
        guard let c = marks?.first?.location?.coordinate else {
            missing.insert(name)
            return nil
        }
        found[name] = c
        return c
    }
}
