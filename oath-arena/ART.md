# 美术替换接口与生成记录

游戏逻辑不读取图片像素，不依赖插画的轮廓。攻击、生命、碰撞、判定都在 `engine.js`，以后替换美术不改变规则。

## 当前素材

- `assets/arena.png`：原始生成的竞技场背景。
- `assets/arena.webp`：网页加载用压缩版本。
- `assets/units.png`：原始生成的12兵种原型透明图集，1254×1254 RGBA。
- `assets/units.webp`：保留透明通道的网页版本。
- 30个兵种目前复用12类立绘。站立浮动、移动起伏、攻击前冲、受击闪白、死亡残影由代码完成，不冒充逐帧角色动画。

两个原始图均通过内置 `image_gen` 生成，非CLI/API回退。仅做PNG→WebP格式压缩；图集切片通过绘制坐标实现，保留原图。

## `art.js` 的 ASSETS

可在默认图集注册之后覆盖任一单位ID。所有路径相对游戏首页，发布到子目录仍可使用。

```js
ASSETS.background = './assets/your-arena.webp';
ASSETS.portraits.u1 = './assets/u1-portrait.webp';
ASSETS.sprites.u1 = {
  url: './assets/u1-sheet.webp',
  frameWidth: 128,
  frameHeight: 128,
  width: 72,
  height: 96,
  animations: {
    idle: {row: 0, frames: 4, fps: 5},
    move: {row: 1, frames: 8, fps: 10},
    attack: {row: 2, frames: 4, fps: 12}
  }
};
ASSETS.effects.shield = {url: './assets/shield-break.webp', size: 100};
ASSETS.audio.click = './assets/click.ogg';
```

也支持无动画单图；以及 `{url, rect:[x,y,w,h], width,height}` 原型图集切片。头像切片另带 `atlasWidth/atlasHeight`。特效替换当前为单图叠加接口；需要复杂序列时扩展事件渲染器即可。战斗事件已经带有类型、时间、源/目标位置和阵营。

## 背景生成提示词（原文）

Use case: stylized-concept. Asset type: production background illustration for a dark fantasy tactical card game's battlefield, NOT a screenshot or UI mockup. A vast midnight cathedral arena of obsidian and weathered ivory stone, symmetrical subtle gold inlaid ritual circles, massive shadowy gothic pillars at the far perimeter, empty tiered galleries above. Camera orthographic elevated top down three-quarter, battlefield horizontal left vs right, very wide landscape 2.2:1 aspect ratio. Main arena floor fills most of image, unobstructed readable flat slate plane, subtle paving texture and sparse fine gilded cracks, suitable for small animated units overlaid later. Blue-black desaturated palette, pale moonlight upper center, restrained warm gold details, rich hand-painted game illustration, atmospheric authoritative ominous grandeur, detailed architecture ONLY along outer upper and side margins, center floor low contrast. No characters, no units, no words, no lettering, no symbols resembling UI, no bars, no card frames. No checkerboards, no tactical grid baked in. Clear floor visible throughout center and foreground. Premium dark fantasy painted boardgame art.

## 图集生成提示词（原文）

Use case: stylized-concept. Asset type: ONE production game sprite atlas, precisely 4 columns by 3 rows, 12 equally sized cells, 1536x1536 square atlas, truly transparent background across all empty pixels, no grid lines, no text. Exactly one isolated FULL BODY miniature dark fantasy tactical unit centered in each cell with large clear margin, consistent orthographic front three-quarter view facing slightly right, feet aligned near bottom of its cell. Rich hand-painted gothic boardgame miniature style, slate blue-black armor, aged gold ornaments, ivory bone, muted teal magic, readable silhouette at 64px, matching an ominous gothic cathedral arena. NOT photorealistic and NOT flat geometry. Row1 left to right: (1) armored knight carrying broad tower shield and sword (2) slim dual sword duelist in dark cloak (3) headless spectral cavalry warrior on a compact armored horse (4) hooded ivory priest with a tall candle staff. Row2 left to right: (5) gigantic chained obsidian colossus bearing a small dead sun on its shoulder (6) cloaked bow archer (7) burdened armored bell bearer with enormous bronze funeral bell (8) chain hook executioner. Row3 left to right: (9) small gothic siege cannon on carriage (10) frost mage robed in dark blue (11) long spear soldier (12) standard bearer with gold-rimmed dark banner. All full bodies entirely within their own cells, weapons also within cells. No foreground terrain, no background environment, no captions, no interface. No overlapping cells. No detached decorations crossing cells. Transparent background, not white, not checkerboard.

实际生成尺寸为1254×1254而非提示词中的1536，因此使用实测的切片坐标。个别武器边缘存在图集生成的局部瑕疵，正式美术应逐兵种替换。
