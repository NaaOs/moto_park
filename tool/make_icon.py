# app_icon_src.png(背景付きのイメージ画像)から、全プラットフォーム用の
# 正方形アイコン app_icon.png を作る。
# 1. 周囲の余白(明るい背景・影)を除去してティールの角丸四角を切り出す
# 2. 角の白をティールで塗りつぶして全面ベタにする(プラットフォーム側で角丸処理されるため)
# 3. 1024x1024 の正方形にする
from PIL import Image, ImageDraw

SRC = 'assets/icon/app_icon_src.png'
OUT = 'assets/icon/app_icon.png'

im = Image.open(SRC).convert('RGB')
w, h = im.size
px = im.load()


def is_bg(r, g, b):
    # 明るい背景・影(白〜薄いグレー)を背景とみなす
    return r > 195 and g > 195 and b > 195


# 1. 前景(アイコン)のバウンディングボックスを求める
minx, miny, maxx, maxy = w, h, 0, 0
for y in range(h):
    for x in range(w):
        r, g, b = px[x, y]
        if not is_bg(r, g, b):
            if x < minx: minx = x
            if y < miny: miny = y
            if x > maxx: maxx = x
            if y > maxy: maxy = y

# 角丸・ベベル(光沢の縁)を取り除くため、バウンディングボックスから内側に
# 少しインセットして切り出す。境界のすぐ内側はティールのベタ面なので、
# これで全面ティールのクリーンな正方形になる。
bw, bh = maxx - minx, maxy - miny
inset = round(min(bw, bh) * 0.05)
minx += inset; miny += inset; maxx -= inset; maxy -= inset

crop = im.crop((minx, miny, maxx + 1, maxy + 1))
cw, ch = crop.size

# ティール色を上辺中央からサンプリング(余白埋め用)
teal = crop.getpixel((cw // 2, 1))
print('cropped', crop.size, 'teal', teal)

# 正方形キャンバス(ティール)に中央配置
side = max(cw, ch)
canvas = Image.new('RGB', (side, side), teal)
canvas.paste(crop, ((side - cw) // 2, (side - ch) // 2))

# 1024x1024 にリサイズ
out = canvas.resize((1024, 1024), Image.LANCZOS)
out.save(OUT)
print('wrote', OUT, out.size)
