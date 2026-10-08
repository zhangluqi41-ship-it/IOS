from PIL import Image, ImageDraw
import os

W = 1024
BG = (0, 105, 92)          # #00695C 品牌绿
WHITE = (255, 255, 255)
GRAY = (168, 199, 190)     # 浅绿灰细节线

img = Image.new('RGB', (W, W), BG)
d = ImageDraw.Draw(img)

# 白色标签卡片（居中略偏上）
lw, lh = 580, 720
x0, y0 = (W - lw) // 2, (W - lh) // 2 - 20
r = 56
d.rounded_rectangle([x0, y0, x0 + lw, y0 + lh], radius=r, fill=WHITE)

# 标签孔（左上）
hole_cx, hole_cy = x0 + 72, y0 + 72
hr = 24
d.ellipse([hole_cx - hr, hole_cy - hr, hole_cx + hr, hole_cy + hr], outline=BG, width=14)

# 标题线（品牌绿粗线）
d.rounded_rectangle([x0 + 120, y0 + 150, x0 + lw - 120, y0 + 212], radius=24, fill=BG)

# 细节线 x2
d.rounded_rectangle([x0 + 120, y0 + 272, x0 + lw - 150, y0 + 320], radius=18, fill=GRAY)
d.rounded_rectangle([x0 + 120, y0 + 362, x0 + lw - 110, y0 + 410], radius=18, fill=GRAY)

# 时钟（右下角，象征效期）
ccx, ccy = x0 + lw - 152, y0 + lh - 152
cr = 66
d.ellipse([ccx - cr, ccy - cr, ccx + cr, ccy + cr], outline=BG, width=14)
d.line([ccx, ccy, ccx, ccy - 44], fill=BG, width=14)
d.line([ccx, ccy, ccx + 36, ccy + 12], fill=BG, width=14)
d.ellipse([ccx - 8, ccy - 8, ccx + 8, ccy + 8], fill=BG)

out = r'D:\AndroidDev\projects\expiry_manager\swiftui\Sources\ExpiryApp\Assets.xcassets\AppIcon.appiconset\AppIcon.png'
os.makedirs(os.path.dirname(out), exist_ok=True)
img.save(out)
print('saved:', out)
print('size:', img.size, 'mode:', img.mode, '(mode=RGB 即无 alpha，符合 iOS 要求)')
