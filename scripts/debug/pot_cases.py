import json, os, re, sys, shutil
d = sys.argv[1]
os.makedirs(os.path.join(d, "photos"), exist_ok=True)
shutil.copy(os.path.join(d, "1793791542974-object.jpg"), os.path.join(d, "photos", "pot.jpg"))
lines = open(os.path.join(d, "pot-instances.txt")).read().splitlines()
best = None
for l in lines:
    m = re.match(r"instance (\d+) box x ([\d.]+)-([\d.]+) y ([\d.]+)-([\d.]+) share ([\d.]+)", l)
    if m:
        v = [float(x) for x in m.groups()[1:]]
        if best is None or v[4] > best[1][4]: best = (m.group(1), v)
cases = []
if best:
    l, (x0, x1, y0, y1, _) = best
    shutil.copy(os.path.join(d, "pot", f"mask-{l}.png"), os.path.join(d, "photos", "pot.ref.png"))
    box = [round(y0 * 1000), round(x0 * 1000), round(y1 * 1000), round(x1 * 1000)]
    cases.append({"id": "pot", "photo": "pot.jpg", "what": "鍋子 2026-11-04", "variants": True,
                  "things": [{"name": "鍋子", "box_2d": box, "reference": "pot.ref.png"}]})
json.dump({"photos": [], "cases": cases}, open(os.path.join(d, "cases.json"), "w"))
print(cases)
