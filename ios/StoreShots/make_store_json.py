"""Writes store.json: the words, stickers and reviews the App Store screenshots show (StoreShot.swift).
Run: python3 make_store_json.py  (writes store.json next to this file)."""
import json, os

TPE = "+08:00"
DAAN = {"ja": "大安区", "en": "Daan District"}
TAMSUI = {"ja": "淡水", "en": "Tamsui"}

def chunk(parts, ja, en):
    return {"parts": parts}, ja, en

def word(key, head, zhuyin, pinyin, cat, ex, meaning, ex_tr, sticker, chunks=(), measure=None, related=(), extra_ex=()):
    """chunks: [(parts, ja, en)], measure: (word, zhuyin, ja, en), related: [(word, kind, reading, ja, en)],
    extra_ex: [(zh, ja, en, chunk_index)]"""
    out = {"key": key, "headword": head, "reading_zhuyin": zhuyin, "pinyin": pinyin, "part_of_speech": "N",
           "category_key": cat, "example_sentence": ex, "language": "zh-TW", "explain": {}, "sticker": sticker}
    for lang in ("ja", "en"):
        i = 0 if lang == "ja" else 1
        extras = {"explain_lang": lang, "frequency_level": 1, "register_scale": 0}
        if chunks:
            extras["usage_chunks"] = [dict(c[0], ja=c[1 + i]) for c in chunks]
            extras["example_chunks"] = [dict(chunks[0][0], ja=chunks[0][1 + i])]
        if measure:
            extras["measure_words"] = [{"word": measure[0], "zhuyin": measure[1], "note": measure[2 + i]}]
        if related:
            extras["related_words"] = [{"word": r[0], "kind": r[1], "reading": r[2], "note": r[3 + i]} for r in related]
        if extra_ex:
            extras["example_v"] = 3
            extras["example_pattern_count"] = len(chunks)
            extras["examples_extra"] = [{"zh": e[0], "ja": e[1 + i], "scene": "", "scene_for": e[0],
                                         "chunks": [dict(chunks[e[3]][0], ja=chunks[e[3]][1 + i])]} for e in extra_ex]
        out["explain"][lang] = {"meaning": meaning[i], "example_translation": ex_tr[i], "extras": extras}
    return out

def P(text, pos, **kw):
    d = {"text": text, "pos": pos}
    d.update(kw)
    return d

def st(sid, when, place, lat, lng, cutout=None, photo=None):
    s = {"id": sid, "taken_at": when, "place": place, "lat": lat, "lng": lng}
    if cutout: s["cutout"] = cutout
    if photo: s["photo"] = photo
    return s

D = "today %s"  # the home's day is the day the shots are taken (DemoDatabase.seedStore)
words = [
    # Today, 大安区: the home's day.
    word("latte", "拿鐵", "ㄋㄚˊ ㄊㄧㄝˇ", "ná tiě", "drink", "我每天早上都喝一杯拿鐵。",
         ("ラテ", "latte"), ("毎朝ラテを一杯飲みます。", "I have a latte every morning."),
         st("store-latte", D % "09:12", DAAN, 25.0263, 121.5436, "latte_cut.png", "latte.png"),
         chunks=[chunk([P("一杯", "M"), P("拿鐵", "N")], "ラテ一杯", "a cup of latte"),
                 chunk([P("冰", "Vs"), P("拿鐵", "N")], "アイスラテ", "iced latte")]),
    word("flowers", "花束", "ㄏㄨㄚ ㄕㄨˋ", "huā shù", "flower", "畢業那天，我送她一束花束。",
         ("花束", "bouquet"), ("卒業の日、彼女に花束を贈った。", "On graduation day, I gave her a bouquet."),
         st("store-flowers", "2026-10-11T17:28:00" + TPE, DAAN, 25.0271, 121.5429, "flowers_cut.png", "flowers.png"),
         chunks=[chunk([P("送", "V", pinyin="sòng"), P("花束", "N")], "花束を贈る", "give a bouquet"),
                 chunk([P("收到", "V", pinyin="shōu dào"), P("花束", "N")], "花束を受け取る", "receive a bouquet"),
                 chunk([P("包裝", "V", pinyin="bāo zhuāng"), P("花束", "N")], "花束を包む", "wrap a bouquet")],
         measure=("束", "ㄕㄨˋ", "花束を数えるいちばん一般的な量詞", "The standard measure word for a bouquet."),
         related=[("捧花", "syn", "ㄆㄥˇ ㄏㄨㄚ", "結婚式で花嫁が持つ花束", "Specifically the bouquet held by a bride at a wedding."),
                  ("花藝", "rel", "ㄏㄨㄚ ㄧˋ", "花を生けて飾る技術", "The art of arranging flowers, often used for bouquets.")],
         extra_ex=[("生日那天，她收到一大束花束。", "誕生日に、彼女は大きな花束を受け取った。", "On her birthday, she received a big bouquet.", 1),
                   ("店員幫我把花束包裝得很漂亮。", "店員さんが花束をきれいに包んでくれた。", "The clerk wrapped the bouquet beautifully for me.", 2)]),
    word("dog", "狗", "ㄍㄡˇ", "gǒu", "animal", "我先去遛狗，等一下就回來。",
         ("犬", "dog"), ("先に犬の散歩に行ってくるね、すぐ戻るよ。", "I'm going to walk the dog first. I'll be right back."),
         st("store-dog", D % "15:40", DAAN, 25.0300, 121.5357, "dog_cut.png", "corgi_photo.png"),
         chunks=[chunk([P("遛", "V", pinyin="liù"), P("狗", "N")], "犬を散歩させる", "walk the dog"),
                 chunk([P("狗", "N"), P("搖", "V", pinyin="yáo"), P("尾巴", "N", pinyin="wěi ba")], "犬が尻尾を振る", "the dog wags its tail")],
         measure=("隻", "ㄓ", "動物を数える量詞", "The measure word for animals."),
         extra_ex=[("我家的狗一看到我就搖尾巴。", "うちの犬は私を見るとすぐ尻尾を振る。", "My dog wags its tail as soon as it sees me.", 1)]),
    word("cake", "蛋糕", "ㄉㄢˋ ㄍㄠ", "dàn gāo", "dessert", "這家的草莓蛋糕很好吃。",
         ("ケーキ", "cake"), ("この店のいちごケーキはおいしい。", "The strawberry cake here is delicious."),
         st("store-cake", D % "14:05", DAAN, 25.0255, 121.5447, "cake_cut.png", "cake.png"),
         chunks=[chunk([P("切", "V"), P("蛋糕", "N")], "ケーキを切る", "cut the cake"),
                 chunk([P("一塊", "M"), P("蛋糕", "N")], "ケーキ一切れ", "a piece of cake")]),
    word("bubbletea", "珍珠奶茶", "ㄓㄣ ㄓㄨ ㄋㄞˇ ㄔㄚˊ", "zhēn zhū nǎi chá", "drink", "我想喝一杯珍珠奶茶。",
         ("タピオカミルクティー", "bubble tea"), ("タピオカミルクティーが一杯飲みたい。", "I'd like a cup of bubble tea."),
         st("store-bubbletea", D % "16:20", DAAN, 25.0282, 121.5418, "bubbletea_cut.png", "bubbletea.png"),
         chunks=[chunk([P("一杯", "M"), P("珍珠奶茶", "N")], "タピオカミルクティー一杯", "a cup of bubble tea")]),
    # Earlier animals (図鑑のギャラリー: 動物 4/9).
    word("cat", "貓", "ㄇㄠ", "māo", "animal", "巷口有一隻貓在睡覺。",
         ("猫", "cat"), ("路地の入口で猫が寝ている。", "A cat is sleeping at the end of the alley."),
         st("store-cat", "2026-10-12T10:20:00" + TPE, DAAN, 25.0330, 121.5390, "cat_cut.png", "cat.png")),
    word("fish", "魚", "ㄩˊ", "yú", "animal", "市場的魚很新鮮。",
         ("魚", "fish"), ("市場の魚はとても新鮮だ。", "The fish at the market is very fresh."),
         st("store-fish", "2026-10-10T08:40:00" + TPE, {"ja": "萬華区", "en": "Wanhua District"}, 25.0350, 121.5000, "fish_cut.png", "fish.png")),
    word("bird", "大笨鳥", "ㄉㄚˋ ㄅㄣˋ ㄋㄧㄠˇ", "dà bèn niǎo", "animal", "公園裡有一隻大笨鳥。",
         ("ゴイサギ（台湾での呼び名）", "night heron (Taiwanese nickname)"), ("公園にゴイサギがいる。", "There's a night heron in the park."),
         st("store-bird", "2026-10-08T07:50:00" + TPE, {"ja": "中正区", "en": "Zhongzheng District"}, 25.0320, 121.5190, "bird_cut.png", "bird.png")),
    # 2026-09-13 (日), 淡水: the map's day.
    word("fort", "紅毛城", "ㄏㄨㄥˊ ㄇㄠˊ ㄔㄥˊ", "hóng máo chéng", "building", "週末我們去淡水的紅毛城。",
         ("紅毛城（淡水の古城）", "Fort San Domingo"), ("週末に淡水の紅毛城へ行った。", "We went to Fort San Domingo in Tamsui at the weekend."),
         st("store-fort", "2026-09-13T14:32:00" + TPE, TAMSUI, 25.1753, 121.4329, None, "map_building.png")),
    word("river", "河邊", "ㄏㄜˊ ㄅㄧㄢ", "hé biān", "water", "我們沿著河邊散步。",
         ("川辺", "riverside"), ("川辺を散歩した。", "We walked along the riverside."),
         st("store-river", "2026-09-13T16:11:00" + TPE, TAMSUI, 25.1695, 121.4400, None, "map_sea.png")),
    word("sunset", "夕陽", "ㄒㄧ ㄧㄤˊ", "xī yáng", "sky", "淡水的夕陽很美。",
         ("夕日", "sunset"), ("淡水の夕日はとてもきれいだ。", "The sunset in Tamsui is beautiful."),
         st("store-sunset", "2026-09-13T17:48:00" + TPE, TAMSUI, 25.1665, 121.4440, None, "map_sunset.png")),
]
# Words reviewed often (復習の記憶の一覧), each with a generated picture.
fill = [("bracelet", "手鍊", "ㄕㄡˇ ㄌㄧㄢˋ", "shǒu liàn", "jewelry", ("ブレスレット", "bracelet")),
        ("lipbalm", "護唇膏", "ㄏㄨˋ ㄔㄨㄣˊ ㄍㄠ", "hù chún gāo", "medicine", ("リップクリーム", "lip balm")),
        ("croissant", "可頌", "ㄎㄜˇ ㄙㄨㄥˋ", "kě sòng", "food", ("クロワッサン", "croissant")),
        ("clipper", "指甲剪", "ㄓˇ ㄐㄧㄚˇ ㄐㄧㄢˇ", "zhǐ jiǎ jiǎn", "tool", ("爪切り", "nail clipper")),
        ("puff", "泡芙", "ㄆㄠˋ ㄈㄨˊ", "pào fú", "dessert", ("シュークリーム", "cream puff"))]
# 紅茶 and 洗碗精 are left out: no picture of theirs (the dex showed an error card, owner 2026-10-31). Each of these
# has a generated picture (sources/<key>.png) and its cutout.
for i, (k, h, z, py, cat, m) in enumerate(fill):
    words.append(word(k, h, z, py, cat, "", m, ("", ""),
                      st("store-" + k, "2026-09-%02dT12:00:00" % (20 + i) + TPE, DAAN, 25.03, 121.54, k + "_cut.png", k + ".png")))

reviews = []
for i, (k, *_r) in enumerate(fill):
    # Learned weeks ago, reviewed on schedule: 94–95% now.
    reviews.append({"sticker": "store-" + k, "ease": 2.6, "interval": 14, "repetitions": 4, "last": -1 - i * 0.2, "due": 13,
                    "history": [{"at": -30, "score": 5, "interval": 1}, {"at": -28, "score": 5, "interval": 3},
                                {"at": -15, "score": 5, "interval": 8}, {"at": -1 - i * 0.2, "score": 5, "interval": 14, "ease": 2.6}]})
for w in words[:14]:
    sid = w["sticker"]["id"]
    reviews.append({"sticker": sid, "ease": 2.5, "interval": 1, "repetitions": 1, "last": -1, "due": 0 if sid == "store-bubbletea" else 2,
                    "history": [{"at": -1, "score": 5, "interval": 1}]})

out = {"camera_photo": "corgi_photo.png", "camera_photo_wide": "corgi_wide.png", "words": words, "reviews": reviews}
json.dump(out, open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "store.json"), "w"), ensure_ascii=False, indent=1)
print(len(words), "words,", len(reviews), "reviews")
