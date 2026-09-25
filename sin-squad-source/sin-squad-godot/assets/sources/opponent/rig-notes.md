# 对手分件v1：接入前检查

image_gen原图exec-add4a26d-2706-43d3-999a-2561ff03159c.png。4列×3行，无文字；按原图实测边界创建AtlasTexture，不要重新绘成矢量块。

行1：头、躯干、左袖上段源、右袖上段源。
行2：左前臂、右前臂、左开手、右推筹码手（掌朝下）。
行3：左夹牌手、右休息手、双手交叠替代件、下衣摆。

Astra目视：墨线和主体身份可用，掌朝下推钱比上一稿准确。重要限制：各格并非相同人体比例，头需要相对躯干统一缩小校准；第一行袖实际画到了腕口，不可直接当一整条上臂再接另一整条前臂，否则双重肘腕。应通过AtlasTexture只取其肩到肘部分并让前臂覆盖接缝；用实时骨架锚点旋转，不用整张图片拉长。若接缝仍明显须重画，不能用粒子遮挡。

还缺腿部步行/落座补帧与闭眼头部；因此本图不是AC01—AC10完整动画验收。不得把逐格淡化冒充关节动作。

生成提示：

Use case: identity-preserve. Asset type: ONE transparent 2D skeletal cutout rig sheet for the same single male opponent character in Image1. Image1 is identity and ink style reference, not the output layout. Need separated body parts, NOT complete character poses. Square PNG with genuine transparency. A clean invisible 4-column by 3-row grid, exactly 12 cells; every isolated piece stays within its own cell with wide transparent gutters. No labels or grid lines. Maintain one common anatomical scale across all pieces: torso about 250 pixels tall if sheet1254px, head about140px tall, forearms about160px long. ROW1 left to right: (1) full head including swept black hair and long pale angular face, no neck shadow rectangle; (2) front-view black double-breasted coat TORSO from collar to waist, no head and no arms, aged brass buttons and watch chain; (3) his left upper-arm black sleeve, vertical with shoulder rounded and elbow joint overlap; (4) his right upper-arm black sleeve matching. ROW2: (1) left forearm sleeve, diagonal bend with elbow cuff and wrist opening but no hand; (2) right forearm sleeve, corresponding; (3) LEFT hand open gently curled, five coherent fingers visible, short wrist; (4) RIGHT hand palm angled DOWN, fingers extended together slightly bent as though pushing a stack of chips across a table, no chips. ROW3: (1) LEFT hand gripping an absent card between thumb and bent fingers, no actual card; (2) RIGHT relaxed hand lightly curled to rest on tabletop, no table; (3) the same character's two thin hands lightly interlaced together as one replacement resting-hands piece; (4) his coat lower skirt/pelvis seated fabric folds as a single piece without legs, matching torso waist. All pieces complete and clean at attachment overlaps; sleeves and hands are NOT attached to torso. Dark scratched woodcut ink lines, bone-white highlights, very muted warm brown, restrained brass, matching original cloth rather than glossy digital rendering. No white background, no checkerboard, no furniture, no text, no faces on torso, no duplicated hands within one piece except interlaced pair. Draw physical believable sleeves and pale anatomical hands, not cartoon blocks. The result is an actual separated puppet parts atlas.
