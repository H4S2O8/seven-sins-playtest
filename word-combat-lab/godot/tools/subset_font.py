# 按游戏里实际用到的字裁剪中文字体（网页版没有系统字体，只能内置）。
# 用法：在 godot/ 目录下  python tools/subset_font.py  [源字体路径]
# 需要：pip install fonttools
import glob, os, sys
from fontTools import subset
from fontTools.ttLib import TTFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "C:/Windows/Fonts/NotoSansSC-VF.ttf"
OUT = "assets/fonts/NotoSansSC-subset.ttf"

chars = set(chr(i) for i in range(32, 127))
for pat in ["scripts/**/*.gd", "data/*.json", "data/*.tsv"]:
    for f in glob.glob(pat, recursive=True):
        chars |= set(c for c in open(f, encoding="utf-8").read() if ord(c) > 126 and c not in "\n\r\t")
chars |= set("０１２３４５６７８９，。！？：；、（）【】《》“”‘’…—·～＋－×÷↑↓←→")

font = TTFont(SRC)
cmap = font.getBestCmap()
missing = sorted(c for c in chars if ord(c) not in cmap)
if missing:
    print("字体里没有这些字符（会显示成方块，请换掉）：", " ".join(missing))
opt = subset.Options()
opt.layout_features = ["*"]
opt.notdef_outline = True
sub = subset.Subsetter(opt)
sub.populate(unicodes=[ord(c) for c in chars if ord(c) in cmap])
sub.subset(font)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
font.save(OUT)
print("已写入", OUT, os.path.getsize(OUT), "字节，共", len(chars), "个字符")
