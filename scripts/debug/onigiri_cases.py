import json, os, re, sys, shutil
d = sys.argv[1]
os.makedirs(os.path.join(d, "photos"), exist_ok=True)
shutil.copy(os.path.join(d, "1793882986365-object.jpg"), os.path.join(d, "photos", "onigiri.jpg"))
inst = []
for l in open(os.path.join(d, "instances.txt")).read().splitlines():
    m = re.match(r"instance (\d+) box x ([\d.]+)-([\d.]+) y ([\d.]+)-([\d.]+) share ([\d.]+)", l)
    if m:
        v = [float(x) for x in m.groups()[1:]]
        inst.append((int(m.group(1)), v))
inst.sort(key=lambda t: -t[1][4])
cases = []
if inst:
    l, (x0, x1, y0, y1, _) = inst[0]
    shutil.copy(os.path.join(d, f"mask-{l}.png"), os.path.join(d, "photos", "onigiri.ref.png"))
    box = [round(y0 * 1000), round(x0 * 1000), round(y1 * 1000), round(x1 * 1000)]
    # What happened on 2026-11-05: 5 names in 2 groups, no position for any (ai_runs positions.with_point 0, locate got 0).
    cases.append({"id": "onigiri-no-positions", "photo": "onigiri.jpg", "what": "as the AI answered: no box, 2 things", "variants": False,
                  "things": [{"name": "飯團", "reference": "onigiri.ref.png"}, {"name": "平底鍋", "check": False}]})
    cases.append({"id": "onigiri-no-positions-alone", "photo": "onigiri.jpg", "what": "no box, 1 thing", "variants": False,
                  "things": [{"name": "飯團", "reference": "onigiri.ref.png"}]})
    cases.append({"id": "onigiri-box", "photo": "onigiri.jpg", "what": "with a box", "variants": True,
                  "things": [{"name": "飯團", "box_2d": box, "reference": "onigiri.ref.png"}]})
json.dump({"photos": [], "cases": cases}, open(os.path.join(d, "cases.json"), "w"), ensure_ascii=False)
print(json.dumps(cases, ensure_ascii=False))
