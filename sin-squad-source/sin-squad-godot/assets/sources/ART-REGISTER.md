# 素材来源与验收

所有本表生成图使用内置image_gen，不调用付费API脚本；原始选定参考为execution-v1/reference/table-approved-A.png。图像需要在场景中再次验收，单张源图合格不等于游戏画面合格。

## table-room-clean-v2.png

- 用途：空场构图/室内远景源层。固定桌面投影参考；不得连同静态桌纹重复盖在另一张桌上。
- 来源：内置生成exec-6e7fa47f-4560-4f3f-b96d-dfce49ad91da.png。
- Astra已看：镜头、黑褐木刻、台面边界与参考接近；人物、手、筹码、椅均已移除。中心墙面补全，不剩静态对手。
- 未验：3D桌与远景拼接、视差接缝、最终屏幕清晰度。尚未是正式完成素材。
- 生成过程：先移除原参考的所有人物、六随从、双手、卡、筹码、杯及其投影，保留空房/木桌/暗红边黑垫/月牙；第二次仅移除远处红椅并补墙。没有改变为现代赌场或光滑3D。

第二次原始提示：

Use case: precise-object-edit. Image1 is the clean plate edit target. Make ONE exact targeted change: remove the large empty red-upholstered chair centered behind the table, including its dark wood frame. Reconstruct the dim dark charcoal-brown wall/paneling behind that removed chair using the existing room inked material; keep the bright overhead lamp glow unchanged. Leave every other element exactly unchanged: camera, 16:9 crop, table edges, scratched wood, red-edged charcoal mat with crescent, candles, curtains, wall shadows. No replacement chair, no people, no cards, no chips, no text. This is a layered game's clean static room/table background; all movable chairs will be separate animated assets.
