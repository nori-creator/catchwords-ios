import Foundation

// album-place.ts / album-day-layout.ts の置き方の計算を 1:1 で移したもの（定数・順序・結果とも同じ）。
// 画面に触らない純粋な関数だけ。浮動小数の演算順も TS と揃えてある。

/// 昔の升目の4通り（TS `AlbumSize`）。
nonisolated enum AlbumSize: String, Codable, Sendable, Hashable, CaseIterable {
    case small, portrait, landscape, large
}

/// 札の置き方（TS `Placement`）。x,y は中心、どちらも台紙の**幅**に対する割合。scale は BASE_WIDTH の倍率、rot は度。
nonisolated struct AlbumPlacement: Hashable, Sendable {
    var x: Double
    var y: Double
    var scale: Double
    var rot: Double
}

/// 紙の上の1枚が占める箱（TS `AlbumBox`）。中心と幅・高さ、台紙の幅に対する割合。
nonisolated struct AlbumBox: Hashable, Sendable {
    var x: Double
    var y: Double
    var w: Double
    var h: Double
}

/// 指の動き（TS `Delta`）。
nonisolated struct AlbumDelta: Hashable, Sendable {
    var dx: Double
    var dy: Double
    var scale: Double
    var rot: Double
}

/// 升目の位置（TS `{ col, row }`）。
nonisolated struct AlbumCell: Hashable, Sendable {
    var col: Int
    var row: Int
}

/// 置き方の計算に要る札の情報（TS `DayLayoutSticker`）。
nonisolated struct DayLayoutSticker: Hashable, Sendable {
    var id: String
    var caption: String?
    var albumOrder: Int?
    var albumSize: AlbumSize?
    var albumX: Double?
    var albumY: Double?
    var albumScale: Double?
    var albumRot: Double?

    init(id: String, caption: String? = nil, albumOrder: Int? = nil, albumSize: AlbumSize? = nil,
         albumX: Double? = nil, albumY: Double? = nil, albumScale: Double? = nil, albumRot: Double? = nil) {
        self.id = id
        self.caption = caption
        self.albumOrder = albumOrder
        self.albumSize = albumSize
        self.albumX = albumX
        self.albumY = albumY
        self.albumScale = albumScale
        self.albumRot = albumRot
    }
}

/// TS `DayLayoutInput`。
nonisolated struct DayLayoutInput {
    var stickers: [DayLayoutSticker]
    /// その札に貼る写真が在るか。
    var hasHero: (String) -> Bool
    /// 読めた写真の縦横比（高さ / 幅）。
    var photoRatio: [String: Double]
    /// 台紙の幅（px）。測れていなければ 0。
    var boardW: Double
    /// 見開き（iPhone Duo を開いて横長）: 2列を左右のページの真ん中へ（`packDay`）。
    var spread: Bool = false
}

/// TS `DayLayoutItem`。
nonisolated struct DayLayoutItem: Hashable, Sendable {
    var id: String
    var place: AlbumPlacement
    var ratio: Double
    /// 重なりの順（後ろほど上）。
    var z: Int
}

/// 自動配置に渡す1枚（`packDay`）。
nonisolated struct CollageItem: Hashable, Sendable {
    var id: String
    var ratio: Double
    var extra: Double = 0
}

nonisolated enum AlbumLayout {
    // MARK: - 定数（album-place.ts）

    /// 升目の横の隙間（16px / 316px）。
    static let GAP_X: Double = 16.0 / 316.0
    /// 升目の縦の隙間（32px / 316px）。
    static let GAP_Y: Double = 32.0 / 316.0
    /// 1升の幅＝ scale 1 の札の幅。
    static let BASE_WIDTH: Double = (1 - 2 * GAP_X) / 3
    /// 1段の高さ（7rem / 316px）。
    static let ROW_H: Double = 112.0 / 316.0
    /// 台紙の高さの下限（幅に対する割合）。
    static let MIN_BOARD_H: Double = 1.25
    /// 大きさの下限と上限。
    static let MIN_SCALE: Double = 0.45
    static let MAX_SCALE: Double = 2.6
    /// 指を離したときにまっすぐへ吸い付く幅（度）。
    static let ROT_SNAP_DEG: Double = 4
    /// 大きさ → 升目（横, 縦）。
    static func SIZE_CELLS(_ size: AlbumSize) -> (Int, Int) {
        switch size {
        case .small: return (1, 1)
        case .portrait: return (1, 2)
        case .landscape: return (2, 1)
        case .large: return (2, 2)
        }
    }

    // 誌面の定数。
    static let COLLAGE_GAP: Double = 0.022
    static let COLLAGE_RATIO_MIN: Double = 0.66
    static let COLLAGE_RATIO_MAX: Double = 1.15

    // 1日のアルバムの自動配置（packDay）の定数。
    /// 自動で置く写真の幅（台紙の幅に対する割合）。どの写真も同じ（オーナー 2026-10-22「1枚目とそれ以降の写真は
    /// 同等に扱って。1枚目だけ大きくするのはへん」）。
    static let DAY_PHOTO_W: Double = 0.44
    /// 1段に2枚並べた時の、写真と写真の間。
    static let DAY_GUTTER: Double = 0.05
    /// 見開き（iPhone Duo を開いて横長、台紙が画面の幅いっぱい）: 写真の幅と、左右のページの真ん中、台紙の高さの下限
    /// （オーナー 2026-10-31「ホーム全体を使って…うまく配置」「左画面と右画面で同じ中心になるように」）。
    static let SPREAD_PHOTO_W: Double = 0.2
    static let SPREAD_COLUMNS: (Double, Double) = (0.22, 0.78)
    static let SPREAD_MIN_BOARD_H: Double = 0.3

    // MARK: - 定数（album-day-layout.ts）

    /// 大きさを保存していない札の既定の並び（TS `AUTO_ALBUM_SIZE`）。
    static let AUTO_ALBUM_SIZE: [AlbumSize] = [.large, .portrait, .small, .landscape, .portrait, .small]
    /// 写真がまだ読めていない札の縦横比。
    static let PLACEHOLDER_RATIO: Double = 1.2
    /// 写真の下の白い余白＋間（px）。
    static let CAP_ROW_PX: Double = 38
    /// 一言（キャプション）3行ぶん（px）。
    static let CAP_NOTE_PX: Double = 56
    /// 写真の無い語の札の高さ（px）。
    static let PLAIN_WORD_PX: Double = 32
    /// 指の当たり判定の下限（px）。
    static let MIN_TAP_PX: Double = 44

    // MARK: - 小さな道具（album-place.ts）

    /// 升目いくつ分 → 幅（TS `cellsWidth`）。
    static func cellsWidth(_ cx: Int) -> Double {
        Double(cx) * BASE_WIDTH + Double(cx - 1) * GAP_X
    }

    /// 升目いくつ分 → 高さ（TS `cellsHeight`、台紙の幅に対する割合）。
    static func cellsHeight(_ cy: Int) -> Double {
        Double(cy) * ROW_H + Double(cy - 1) * GAP_Y
    }

    /// 大きさ → 初期の倍率（TS `scaleOf`）。
    static func scaleOf(_ size: AlbumSize) -> Double {
        cellsWidth(SIZE_CELLS(size).0) / BASE_WIDTH
    }

    /// −180〜180 に畳む（TS `normalizeDeg`、JS の % ＝ truncatingRemainder）。
    static func normalizeDeg(_ deg: Double) -> Double {
        var d = (deg + 180).truncatingRemainder(dividingBy: 360) - 180
        if d < -180 { d += 360 }
        return d
    }

    /// 数を範囲に収める（TS `clamp`、NaN はそのまま通る）。
    static func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v < lo ? lo : v > hi ? hi : v
    }

    /// 掴んだときの置き方に指の動きを足す（TS `applyDelta`）。boardW は px、maxY は縦の上限。
    static func applyDelta(_ base: AlbumPlacement, _ d: AlbumDelta, boardW: Double, maxY: Double) -> AlbumPlacement {
        let w = Swift.max(boardW, 1)
        return AlbumPlacement(
            x: clamp(base.x + d.dx / w, 0, 1),
            y: clamp(base.y + d.dy / w, 0, Swift.max(maxY, 0)),
            scale: clamp(base.scale * d.scale, MIN_SCALE, MAX_SCALE),
            rot: normalizeDeg(base.rot + d.rot)
        )
    }

    /// 指を離したとき、まっすぐの近くだけ 0 度に直す（TS `settle`）。
    static func settle(_ p: AlbumPlacement) -> AlbumPlacement {
        guard abs(normalizeDeg(p.rot)) <= ROT_SNAP_DEG else { return p }
        var q = p
        q.rot = 0
        return q
    }

    /// 札の実寸 px（TS `sizePx`、傾きは含まない）。
    static func sizePx(_ p: AlbumPlacement, boardW: Double, ratio: Double) -> (w: Double, h: Double) {
        let w = boardW * BASE_WIDTH * p.scale
        return (w, w * ratio)
    }

    /// JS の `(hash * 31 + charCodeAt(i)) >>> 0` と同じ値（UTF-16 単位・UInt32 で折り返す）。
    static func idHash(_ id: String) -> UInt32 {
        var hash: UInt32 = 0
        for u in id.utf16 { hash = hash &* 31 &+ UInt32(u) }
        return hash
    }

    /// 升目の位置と大きさ → 置き方（TS `placeFromCell`、傾きは id から −3.5〜3.5 度）。
    static func placeFromCell(_ cell: AlbumCell, _ size: AlbumSize, id: String) -> AlbumPlacement {
        let (cx, cy) = SIZE_CELLS(size)
        let w = cellsWidth(cx)
        let h = cellsHeight(cy)
        let hash = idHash(id)
        return AlbumPlacement(
            x: Double(cell.col) * (BASE_WIDTH + GAP_X) + w / 2,
            y: Double(cell.row) * (ROW_H + GAP_Y) + h / 2,
            scale: scaleOf(size),
            rot: (Double(hash % 71) / 70) * 7 - 3.5
        )
    }

    /// 台紙の高さ（幅に対する割合、TS `boardHeight`）。
    static func boardHeight(_ items: [(place: AlbumPlacement, ratio: Double)], minH: Double = MIN_BOARD_H) -> Double {
        var bottom: Double = 0
        for it in items {
            let h = BASE_WIDTH * it.place.scale * it.ratio
            bottom = jsMax(bottom, it.place.y + h / 2)
        }
        return jsMax(minH, bottom + GAP_Y)
    }

    /// DayLayoutItem 版の `boardHeight`。
    static func boardHeight(_ items: [DayLayoutItem], minH: Double = MIN_BOARD_H) -> Double {
        boardHeight(items.map { (place: $0.place, ratio: $0.ratio) }, minH: minH)
    }

    /// 保存された値を置き方に直す。欠けた値は自動に倒す（TS `placementFrom`）。
    static func placementFrom(x: Double?, y: Double?, scale: Double?, rot: Double?, auto: AlbumPlacement) -> AlbumPlacement {
        func num(_ v: Double?, _ fallback: Double) -> Double {
            if let v, v.isFinite { return v }
            return fallback
        }
        return AlbumPlacement(
            x: clamp(num(x, auto.x), 0, 1),
            y: jsMax(num(y, auto.y), 0),
            scale: clamp(num(scale, auto.scale), MIN_SCALE, MAX_SCALE),
            rot: normalizeDeg(num(rot, auto.rot))
        )
    }

    /// 比を誌面の範囲へ。壊れた値は 1（TS `collageRatio`）。
    static func collageRatio(_ ratio: Double) -> Double {
        let r = ratio.isFinite && ratio > 0 ? ratio : 1
        return clamp(r, COLLAGE_RATIO_MIN, COLLAGE_RATIO_MAX)
    }

    /// id から決まる 0〜1（TS `packCollage` 内の `seed`、FNV-1a＋仕上げの攪拌）。写真の傾きに使う。
    static func seed(_ id: String, _ salt: UInt32) -> Double {
        var h: UInt32 = 0x811c9dc5 ^ salt
        for u in id.utf16 {
            h ^= UInt32(u)
            h = h &* 0x01000193
        }
        h ^= h >> 15
        h = h &* 0x2545f491
        h ^= h >> 13
        return Double(h) / 4294967296
    }

    /// 傾けた札を包む箱、字（extra）は下に足す（TS `boxOf`）。
    static func boxOf(_ p: AlbumPlacement, ratio: Double, extra: Double = 0) -> AlbumBox {
        let w = p.scale * BASE_WIDTH
        let h = w * (ratio.isFinite && ratio > 0 ? ratio : 1)
        let t = (abs(p.rot) * Double.pi) / 180
        let bw = w * cos(t) + h * sin(t)
        let bh = w * sin(t) + h * cos(t)
        return AlbumBox(x: p.x, y: p.y + extra / 2, w: bw, h: bh + extra)
    }

    /// 2つの箱が（余白 pad 込みで）かかるか（TS `boxesOverlap`）。
    static func boxesOverlap(_ a: AlbumBox, _ b: AlbumBox, pad: Double = COLLAGE_GAP / 2) -> Bool {
        abs(a.x - b.x) < (a.w + b.w) / 2 + pad && abs(a.y - b.y) < (a.h + b.h) / 2 + pad
    }

    /// 1日のアルバムの自動配置（オーナー 2026-10-22「その日の欄の1枚目は真ん中に」「決してほかの画像には被らない
    /// ように上から順に配置して」「1枚目とそれ以降の写真は同等に扱って」）。撮った順に、どれも同じ幅で:
    /// - 2枚ずつの段に左右へ並べ、段に1枚だけの写真（最後の1枚）は中央。段は前の段の下から。
    /// - 指で置いた写真（`fixed`）が在る日は、どの写真も、上から見て最初に空いている所へ（自分の段の位置 → 中央 →
    ///   左 → 右の順に試す）。指で置いた写真にも、先に置いた写真にも決して重ならない。
    /// - 指で置いた写真が無く、写真が台紙の高さの下限に足りない日は、写真のまとまりを台紙の縦の真ん中へ。
    static func packDay(_ items: [CollageItem], fixed: [AlbumBox] = [], spread: Bool = false) -> [AlbumPlacement] {
        func safeRatio(_ r: Double) -> Double { r.isFinite && r > 0 ? r : 1 }
        if spread && fixed.isEmpty { return packSpread(items) }
        let w = spread ? SPREAD_PHOTO_W : DAY_PHOTO_W
        let scale = w / BASE_WIDTH
        let left = spread ? SPREAD_COLUMNS.0 : 0.5 - DAY_GUTTER / 2 - w / 2
        let right = spread ? SPREAD_COLUMNS.1 : 0.5 + DAY_GUTTER / 2 + w / 2
        var taken = fixed
        var out: [AlbumPlacement] = []
        out.reserveCapacity(items.count)
        var rowTop: Double = 0
        var rowBottom: Double = 0
        for (i, it) in items.enumerated() {
            let alone = i % 2 == 0 && i == items.count - 1
            let x = alone ? 0.5 : (i % 2 == 0 ? left : right)
            let rot = alone
                ? (seed(it.id, 17) < 0.5 ? -1 : 1) * (0.6 + seed(it.id, 13) * 1.2)
                : (i % 2 == 0 ? -1 : 1) * (1 + seed(it.id, 13) * 1.5)
            var p = AlbumPlacement(x: x, y: 0, scale: scale, rot: rot)
            // 傾けた写真の箱の、写真ぶんの高さ（字の extra を除く）。箱の上端 = y − bh / 2。
            let bh = boxOf(p, ratio: safeRatio(it.ratio), extra: it.extra).h - it.extra
            if fixed.isEmpty {
                if i % 2 == 0 { rowTop = rowBottom }
                p.y = rowTop + bh / 2
                rowBottom = Swift.max(rowBottom, rowTop + bh + it.extra + COLLAGE_GAP)
            } else {
                p = firstFree(p, xs: [x, 0.5, left, right], halfH: bh / 2, ratio: safeRatio(it.ratio), extra: it.extra,
                              taken: taken)
            }
            taken.append(boxOf(p, ratio: safeRatio(it.ratio), extra: it.extra))
            out.append(p)
        }
        // 写真が少ない日は、まとまりを台紙の縦の真ん中へ（1枚なら真ん中に1枚）。
        if fixed.isEmpty, !out.isEmpty {
            let room = (spread ? SPREAD_MIN_BOARD_H : MIN_BOARD_H) - GAP_Y - (rowBottom - COLLAGE_GAP)
            if room > 0 { out = out.map { var q = $0; q.y += room / 2; return q } }
        }
        return out
    }

    /// 見開き（iPhone Duo を開いて横長）の1日（オーナー 2026-10-31「縦横に無機質に置きすぎ…切り抜き画像が映えるように
    /// 配置デザインそれぞれの大きさを工夫して」、同日「4つに絞って、一つ一つを少し大きく、有機的に並べて」→ 案1「対角の流れ」）:
    /// 4枚ずつの組を、横の4つの通り道へ撮った順に1枚ずつ。1枚目は左上に大きく、2枚目は右のページの上、3枚目は左のページの
    /// 内側の下、4枚目は右の外側の下。左上から右下へゆるく下る対角の流れで、大きさと傾きを少しずつ変える。
    /// 通り道は横に離してあり、もし箱がかかる時は下の写真を下げる（決して重ならない）。組に1枚だけ残った写真は真ん中。
    private static let SPREAD_PATTERN: [(x: Double, w: Double, top: Double, rot: Double)] = [
        (0.14, 0.26, 0.01, -5.0),
        (0.655, 0.23, 0.00, 4.0),
        (0.40, 0.18, 0.19, 3.0),
        (0.90, 0.18, 0.21, -4.0),
    ]

    private static func packSpread(_ items: [CollageItem]) -> [AlbumPlacement] {
        func safeRatio(_ r: Double) -> Double { r.isFinite && r > 0 ? r : 1 }
        var out: [AlbumPlacement] = []
        out.reserveCapacity(items.count)
        var placed: [AlbumBox] = []
        var blockTop: Double = 0
        var bottom: Double = 0
        var start = 0
        while start < items.count {
            let block = Array(items[start..<min(items.count, start + SPREAD_PATTERN.count)])
            var blockBottom = blockTop
            for (k, it) in block.enumerated() {
                let slot = SPREAD_PATTERN[k]
                let alone = block.count == 1
                var p = AlbumPlacement(x: alone ? 0.5 : slot.x, y: 0, scale: slot.w / BASE_WIDTH,
                                       rot: slot.rot + (seed(it.id, 13) - 0.5))
                let bh = boxOf(p, ratio: safeRatio(it.ratio), extra: it.extra).h - it.extra
                var top = blockTop + (alone ? 0 : slot.top)
                p.y = top + bh / 2
                // Never overlap: if this photo's box touches one already placed, move it below that one.
                for _ in 0..<out.count {
                    let box = boxOf(p, ratio: safeRatio(it.ratio), extra: it.extra)
                    guard let hit = placed.first(where: { boxesOverlap(box, $0) }) else { break }
                    let push = (hit.y + hit.h / 2 + COLLAGE_GAP) - (box.y - box.h / 2)
                    top += Swift.max(push, 0.001)
                    p.y = top + bh / 2
                }
                placed.append(boxOf(p, ratio: safeRatio(it.ratio), extra: it.extra))
                blockBottom = Swift.max(blockBottom, top + bh + it.extra + COLLAGE_GAP)
                out.append(p)
            }
            bottom = blockBottom
            blockTop = blockBottom
            start += block.count
        }
        let room = SPREAD_MIN_BOARD_H - GAP_Y - (bottom - COLLAGE_GAP)
        if room > 0 { out = out.map { var q = $0; q.y += room / 2; return q } }
        return out
    }

    /// 上から見て最初に空いている所（`packDay`）。試す上端は 0 と、置いてある写真それぞれの下端＋間。同じ上端では
    /// `xs` の順に試す。
    private static func firstFree(_ p: AlbumPlacement, xs: [Double], halfH: Double, ratio: Double, extra: Double,
                                  taken: [AlbumBox]) -> AlbumPlacement {
        let tops = ([0] + taken.map { $0.y + $0.h / 2 + COLLAGE_GAP }).filter { $0 >= 0 }.sorted()
        for top in tops {
            for x in xs {
                var q = p
                q.x = x
                q.y = top + halfH
                let b = boxOf(q, ratio: ratio, extra: extra)
                if !taken.contains(where: { boxesOverlap(b, $0) }) { return q }
            }
        }
        // 一番下の写真の下なら必ず空いている（tops の最後）。ここへは来ない。
        var q = p
        q.y = (tops.last ?? 0) + halfH
        return q
    }

    // MARK: - 1日のアルバム（album-day-layout.ts）

    /// album_order の昇順、欠けは最後（TS `byOrder`、Array.sort と同じく安定）。
    static func sortedByOrder(_ stickers: [DayLayoutSticker]) -> [DayLayoutSticker] {
        let maxSafe = 9_007_199_254_740_991  // Number.MAX_SAFE_INTEGER
        return stickers.enumerated().sorted { l, r in
            let a = l.element.albumOrder ?? maxSafe
            let b = r.element.albumOrder ?? maxSafe
            return a != b ? a < b : l.offset < r.offset
        }.map(\.element)
    }

    /// その札の枠の縦横比を返す関数（TS `dayFrameRatio`）。
    static func dayFrameRatio(_ input: DayLayoutInput) -> (String) -> Double {
        let hasNote = Dictionary(input.stickers.map { ($0.id, jsTruthy($0.caption)) }, uniquingKeysWith: { _, new in new })
        let narrowest = jsMax(input.boardW * (input.spread ? SPREAD_PHOTO_W : DAY_PHOTO_W), 1)
        let hasHero = input.hasHero
        let photoRatio = input.photoRatio
        let boardW = input.boardW
        return { id in
            if hasHero(id) { return collageRatio(photoRatio[id] ?? PLACEHOLDER_RATIO) }
            let timeLine: Double = narrowest < 130 ? 14 : 0
            let px = jsMax(PLAIN_WORD_PX + timeLine + ((hasNote[id] ?? false) ? CAP_NOTE_PX : 0), MIN_TAP_PX)
            return jsTruthy(boardW) ? px / narrowest : 0.3
        }
    }

    /// 写真の下に足す字のぶん（TS `dayExtra`）。字だけの札は 0。
    static func dayExtra(_ s: DayLayoutSticker, hasHero: Bool, boardW: Double) -> Double {
        hasHero && jsTruthy(boardW) ? (CAP_ROW_PX + (jsTruthy(s.caption) ? CAP_NOTE_PX : 0)) / boardW : 0
    }

    /// 自動の置き場所を決め、保存した写真を避ける（TS `settleDayAlbum`）。
    static func settleDayAlbum(_ input: DayLayoutInput) -> (frameRatio: (String) -> Double, settledById: [String: AlbumPlacement]) {
        let stickers = input.stickers
        let hasHero = input.hasHero
        let boardW = input.boardW
        let frameRatio = dayFrameRatio(input)
        let base = sortedByOrder(stickers)
        func item(_ s: DayLayoutSticker) -> CollageItem {
            CollageItem(id: s.id, ratio: frameRatio(s.id), extra: dayExtra(s, hasHero: hasHero(s.id), boardW: boardW))
        }
        let places = packDay(base.map(item), spread: input.spread)
        var autoById: [String: AlbumPlacement] = [:]
        for (i, s) in base.enumerated() { autoById[s.id] = places[i] }

        func saved(_ s: DayLayoutSticker) -> Bool { s.albumX != nil && s.albumY != nil }
        let fixed: [AlbumBox] = stickers.filter(saved).map { s in
            let p = placementFrom(
                x: s.albumX, y: s.albumY, scale: s.albumScale, rot: s.albumRot,
                auto: autoById[s.id] ?? placeFromCell(AlbumCell(col: 0, row: 0), .small, id: s.id)
            )
            return boxOf(p, ratio: frameRatio(s.id), extra: dayExtra(s, hasHero: hasHero(s.id), boardW: boardW))
        }
        if fixed.isEmpty { return (frameRatio, autoById) }

        // 指で置いていない写真は撮った順に、上から見て最初に空いている所へ（`packDay`）。
        let autos = base.filter { !saved($0) }
        let settled = packDay(autos.map(item), fixed: fixed, spread: input.spread)
        var settledById = autoById
        for (i, s) in autos.enumerated() { settledById[s.id] = settled[i] }
        return (frameRatio, settledById)
    }

    /// 札の本当の置き方：指で置いた値が在ればそれ、無ければ自動（TS `dayPlacement`）。
    static func dayPlacement(_ s: DayLayoutSticker, settledById: [String: AlbumPlacement], size: AlbumSize) -> AlbumPlacement {
        placementFrom(
            x: s.albumX, y: s.albumY, scale: s.albumScale, rot: s.albumRot,
            auto: settledById[s.id] ?? placeFromCell(AlbumCell(col: 0, row: 0), size, id: s.id)
        )
    }

    /// 1日の全体と台紙の高さ（TS `layoutDayAlbum`）。
    static func layoutDayAlbum(_ input: DayLayoutInput) -> (items: [DayLayoutItem], boardH: Double) {
        let (frameRatio, settledById) = settleDayAlbum(input)
        let ordered = sortedByOrder(input.stickers)
        let items = ordered.enumerated().map { i, s in
            DayLayoutItem(
                id: s.id,
                place: dayPlacement(s, settledById: settledById,
                                    size: s.albumSize ?? AUTO_ALBUM_SIZE[i % AUTO_ALBUM_SIZE.count]),
                ratio: frameRatio(s.id),
                z: 10 + i
            )
        }
        return (items, boardHeight(items, minH: input.spread ? SPREAD_MIN_BOARD_H : MIN_BOARD_H))
    }

    // MARK: - JS の意味に合わせる小道具

    /// JS `Math.max`（どちらかが NaN なら NaN）。
    static func jsMax(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : Swift.max(a, b)
    }

    /// JS `Math.min`（どちらかが NaN なら NaN）。
    static func jsMin(_ a: Double, _ b: Double) -> Double {
        a.isNaN || b.isNaN ? .nan : Swift.min(a, b)
    }

    /// JS の真偽（0 と NaN は偽）。
    static func jsTruthy(_ v: Double) -> Bool { v != 0 && !v.isNaN }

    /// JS の真偽（nil と空文字は偽）。
    static func jsTruthy(_ v: String?) -> Bool { !(v ?? "").isEmpty }
}
