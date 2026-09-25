# 第一人称手姿源图

player-hand-poses-v2.png，内置image_gen，1024×1536，2列3行。源exec-b0a6538e-9e65-489e-82da-9cb54025f7d3.png；上一版exec-00f9d018-6b2b-4de0-8813-d68db5c56a63.png未接入。风格参考execution-v1/reference/table-approved-A.png。

右列：休息、掌心向下推钱、指向。左列：握牌、夹牌、张掌。Astra已看墨线与右手推姿，已逐点读alpha：图外(80,80)、(500,200)、(500,500)、(600,40)、(160,220)、(600,500)、(10,10)均alpha0。图片查看器显示的棕色晕染可能是透明像素RGB，不能仅凭其预览判断有实心背景；Godot导入必须保留alpha、边缘fix处理要核查实际桌面。

待验收：左列各姿势的拇指与手腕方向仍须按第一人称统一，张掌图不直接认为已正确；允许显示层镜像调整某姿势的朝向，但必须与持牌手连续，不能瞬间变左右手。握牌时应手掌在牌后、拇指在牌前，可用源图纹理裁片/遮罩单独显示拇指层；不把三张卡烘焙进手。仅已有姿势，不是已完成发牌动画。

生成提示摘要：第一人称六手姿，2列3行，统一旧黑袖、骨白墨线，不画牌和筹码，透明底。v2最终编辑提示：

Use case: precise-object-edit. EDIT TARGET is image 1: the 2-column 3-row ink hand atlas. Preserve the hand drawing quality, palette, six poses and each cell's size. Two exact corrections only. First remove ALL brown aura/vignette/drop-shadow/backdrop around every hand: beyond the ink contour every pixel must be alpha=0, genuine clear transparent background, crisp clean silhouette anti-aliased only at edge. No painted black background, no soft brown glow. Second LEFT column must be anatomically a LEFT hand as seen by the owner looking down: wrist enters from bottom-left, fingers toward top-right, the thumb lies toward the inside/right of the palm rather than the current outside/left; correct or reflect just each left-column hand's anatomy/orientation as needed for a FIRST PERSON LEFT hand. Left top receives a fan of imaginary cards between thumb front and fingers behind; left middle pinches one imaginary card; left bottom open release left palm with thumb on its right side. Keep RIGHT column exactly the same, it is the owner's RIGHT hand: resting, pushing with palm DOWN, pointing. All hands have exactly five fingers. Do not draw objects, cards or chips. No text. No layout changes. Full transparent cutouts ready to place over a dark wood table without rectangular blocks or halos.
