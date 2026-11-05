import json, os, sys, shutil
d = sys.argv[1]
os.makedirs(os.path.join(d, "photos"), exist_ok=True)
shutil.copy(os.path.join(d, "1793856943049-encounter.jpg"), os.path.join(d, "photos", "curry.jpg"))
shutil.copy(os.path.join(d, "mask-1.png"), os.path.join(d, "photos", "curry.ref.png"))
bowl = {"name": "咖哩飯", "box_2d": [263, 137, 769, 887], "reference": "curry.ref.png"}
cut = {"name": "豬排", "box_2d": [340, 240, 620, 690]}
broc = {"name": "花椰菜", "box_2d": [560, 300, 720, 800]}
cases = [
  {"id": "curry-alone", "photo": "curry.jpg", "what": "curry only", "things": [bowl]},
  {"id": "curry-cutlet", "photo": "curry.jpg", "what": "curry and cutlet", "things": [bowl, cut]},
  {"id": "curry-cutlet-broccoli", "photo": "curry.jpg", "what": "curry, cutlet, broccoli", "things": [bowl, cut, broc]},
]
json.dump({"photos": [], "cases": cases}, open(os.path.join(d, "cases.json"), "w"), ensure_ascii=False)
