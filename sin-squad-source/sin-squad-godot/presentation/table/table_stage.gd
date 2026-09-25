extends Node3D

const CALIBRATION_SCENE := preload("res://presentation/calibration/calibration.tscn")
const CARD_VIEW_SCRIPT := preload("res://presentation/cards/card_view.gd")
const CHIP_STACK_SCRIPT := preload("res://presentation/chips/chip_stack.gd")
const HAND_RIG_SCRIPT := preload("res://presentation/hands/hand_rig.gd")
const DEALER_RIG_SCRIPT := preload("res://presentation/hands/dealer_rig.gd")
const OPPONENT_ENTRY_SCRIPT := preload("res://presentation/table/opponent_entry_rig.gd")
const SESSION_SCRIPT := preload("res://core/session/session.gd")
const COMMAND_SCRIPT := preload("res://core/types/command.gd")
const APP_CONTROLLER_SCRIPT := preload("res://core/app/app_controller.gd")
const CONTENT_DETAILS_SCRIPT := preload("res://presentation/table/content_details.gd")
const CARD_ATLAS := "res://assets/sources/cards/card-frames-v1.png"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Full.ttf"
const PLAYER_DEMOS := [
	{"id": "EQ01", "title": "校准刃", "body": "攻击 +3\n演示候选一\n点击后选装备槽安装"},
	{"id": "EQ02", "title": "厚衬背心", "body": "生命上限 +18\n演示候选二\n点击后选装备槽安装"},
	{"id": "EQ03", "title": "轻摆齿轮", "body": "攻击间隔 −0.2秒\n演示候选三\n点击后选装备槽安装"},
]
const CHIP_DENOMINATIONS := [1, 5, 25, 100]
const CHIP_INKS := [Color("6f3028"), Color("312a24"), Color("79633b"), Color("b5a47e")]
const ACTIONS := [
	[12, "AC12 发单牌"], [13, "AC13 整理牌叠"], [14, "AC14 收弃牌"], [15, "AC15 左手接牌"], [16, "AC16 扇开三牌"],
	[17, "AC17 检视所选牌"], [18, "AC18 推筹码入池"], [19, "AC19 收回筹码"], [20, "AC20 卡牌翻面"], [21, "AC21 展开三候选"],
	[22, "AC22 安装进扣槽"], [23, "AC23 交换同类槽"], [24, "AC24 改主攻指向"], [25, "AC25 翻同意签"], [26, "AC26 竞价筹码移动"],
	[27, "AC27 六位公开占牌"], [28, "AC28 配置锁定提示"], [29, "AC29 奖池视觉结算"], [30, "AC30 清桌物件归位"], [31, "AC31 离桌物件退场"], [32, "AC32 标题牌预览"],
]
const SLOT_IDS := [
	"P1_SLOT_EQ", "P1_SLOT_FX", "P2_SLOT_EQ", "P2_SLOT_FX", "P3_SLOT_EQ", "P3_SLOT_FX",
	"O1_SLOT_EQ", "O1_SLOT_FX", "O2_SLOT_EQ", "O2_SLOT_FX", "O3_SLOT_EQ", "O3_SLOT_FX",
]
const ACTION_SECONDS := {
	12: 0.65, 13: 0.70, 14: 0.70, 15: 0.28, 16: 0.35, 17: 0.38, 18: 0.65, 19: 0.75,
	20: 0.32, 21: 0.45, 22: 0.60, 23: 0.55, 24: 0.20, 25: 0.35, 26: 0.65,
	27: 0.90, 28: 0.40, 29: 1.50, 30: 1.40, 31: 1.20, 32: 0.60,
}

var composition
var camera: Camera3D
var card_texture: Texture2D
var font: Font
var player_cards: Array[Node3D] = []
var opponent_cards: Array[Node3D] = []
var player_chip_stacks: Array[Node3D] = []
var opponent_chip_stacks: Array[Node3D] = []
var flying_chip: Node3D
var pot_tray: Node3D
var slot_areas: Dictionary = {}
var slot_meshes: Dictionary = {}
var dealers
var player_hands
var opponent_entry
var entry_chair: Node3D
var dealer_home_transforms: Dictionary = {}
var player_contact := Vector3.ZERO
var opponent_contact := Vector3.ZERO
var ray_marker: MeshInstance3D
var sign_nodes: Array[Node3D] = []
var entry_start_positions: Dictionary = {}
var entry_target_positions: Dictionary = {}
var action_tween: Tween
var entry_elapsed := 4.8
var entry_playing := false
var entry_ready := true
var selected_card_index := -1
var selected_slot := "P1_SLOT_EQ"
var active_action := -1
var action_log: Array[int] = []
var action_busy := false
var demo_amounts := {"player": 250, "opponent": 250, "pot": 50}
var ui_layer: CanvasLayer
var ui_root: Control
var status_label: Label
var readout_label: Label
var action_select: OptionButton
var slot_select: OptionButton
var entry_slider: HSlider
var entry_time_label: Label
var entry_play_button: Button
var action_play_button: Button
var install_button: Button
var slot_labels: Dictionary = {}
var amount_labels: Dictionary = {}
var intro_camera_transform: Transform3D
var title_banner: Label
var last_hit: Dictionary = {}

# The stage is still a self-contained visual prototype, but its opening team
# selection now goes through the real Session/AppController command path.  The
# existing equipment/slot preview controls below remain intentionally untouched.
var game_session: SinSession
var game_controller: SinAppController
var team_panel: PanelContainer
var team_status_label: Label
var team_slot_rows: Dictionary = {}
var team_choice_buttons: Dictionary = {}
var team_reroll_buttons: Dictionary = {}
var team_command_serial := 0
var character_names: Dictionary = {}
var character_details: Dictionary = {}
var attachment_details: Dictionary = {}
var environment_details: Dictionary = {}
var rule_details: Dictionary = {}
var game_panel: PanelContainer
var game_phase_label: Label
var game_context_label: Label
var game_action_box: VBoxContainer
var draft_slot_select: OptionButton
var game_command_serial := 0
var game_ui_signature := ""
var automatic_action_cooldown := 0.0
var replay_notice := ""
var hover_detail_panel: PanelContainer
var hover_detail_label: Label
var hovered_detail_id := ""
var hovered_detail_owner := ""
var content_detail_catalog: SinContentDetails
var tutorial_panel: PanelContainer
var tutorial_title_label: Label
var tutorial_body_label: Label
var tutorial_toggle_button: Button
var tutorial_enabled := true
var tutorial_ui_signature := ""
var tutorial_completed_persisted := false
var tutorial_last_phase := ""
const TUTORIAL_COMPLETION_PATH := "user://sin_squad_first_table_tutorial_completed.save"


func _ready() -> void:
	print("W05READY 01 before font load")
	card_texture = load(CARD_ATLAS) as Texture2D
	font = load(FONT_PATH) as Font
	_load_character_names()
	_load_content_details()
	tutorial_completed_persisted = _is_tutorial_completed()
	tutorial_enabled = not tutorial_completed_persisted
	game_session = SESSION_SCRIPT.new({"seed": 20260924, "first_actor": "player", "team_draft": true,
		"player_table": 100, "opponent_table": 100, "ante": 0})
	# The table uses the normal release admission path.  The session pools are
	# already filtered to handlers that explicitly advertise real support.
	game_controller = APP_CONTROLLER_SCRIPT.new(game_session, null, false)
	print("W05READY 02 after font load")
	print("W05READY 03 before calibration instantiate")
	composition = CALIBRATION_SCENE.instantiate()
	print("W05READY 04 after calibration instantiate")
	composition.debug_mode = false
	composition.parallax_enabled = false
	print("W05READY 05 before calibration add_child")
	add_child(composition)
	print("W05READY 06 after calibration add_child")
	composition._apply_debug_mode(false)
	composition.ui_layer.visible = false
	composition.overlay.visible = false
	camera = composition.camera
	print("W05READY 07 before light and table detail")
	_make_light()
	_build_table_detail()
	print("W05READY 08 before _build_slots")
	_build_slots()
	print("W05READY 09 after _build_slots / before _build_card_views")
	_build_card_views()
	print("W05READY 10 after _build_card_views / before _build_chips")
	_build_chips()
	print("W05READY 11 after _build_chips / before _build_player_hands")
	_build_player_hands()
	print("W05READY 12 after _build_player_hands / before _build_dealers")
	_build_dealers()
	_build_entry_character_and_chair()
	print("W05READY 13 after _build_dealers / before _build_stage_ui")
	_build_stage_ui()
	_build_hover_detail_ui()
	_build_team_selection_ui()
	_build_game_loop_ui()
	_build_quick_tutorial_ui()
	print("W05READY 14 after _build_stage_ui / before final layout")
	_update_screen_labels()
	_update_team_selection_ui()
	_refresh_game_loop_ui(true)
	tutorial_last_phase = str(game_session.state.phase)
	get_viewport().size_changed.connect(_on_viewport_resized)
	entry_elapsed = 4.8
	_apply_entry_time(entry_elapsed)


func _make_light() -> void:
	var light := DirectionalLight3D.new()
	light.name = "SoftTableKeyLight"
	light.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(-22.0), 0.0)
	light.light_energy = 0.45
	light.light_color = Color("e2cfaa")
	add_child(light)


func _build_table_detail() -> void:
	var line := MeshInstance3D.new()
	line.name = "LaneGuidePreview"
	var immediate := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.72, 0.56, 0.34, 0.66)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for lane in range(3):
		var lane_x := -2.15 + lane * 2.15
		immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
		immediate.surface_add_vertex(Vector3(lane_x, 0.06, 1.45))
		immediate.surface_add_vertex(Vector3(lane_x, 0.06, -1.28))
		immediate.surface_end()
	line.mesh = immediate
	add_child(line)

	ray_marker = MeshInstance3D.new()
	ray_marker.name = "AimPreviewLine3D"
	add_child(ray_marker)

	var opponent_proxy: Node3D = composition.get_node_or_null("OpponentPoseProxyAnchor")
	if opponent_proxy != null:
		opponent_proxy.visible = true


func _build_slots() -> void:
	for slot_id: String in SLOT_IDS:
		var target: Vector3 = composition.target_points[slot_id]
		var center: Vector3 = composition._world_at_screen_point(Vector2(target.x, target.y), target.z)
		var slot := Node3D.new()
		slot.name = slot_id + "_PhysicalCardFastener"
		slot.position = center + Vector3.UP * 0.018
		add_child(slot)
		var plate := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 0.12
		disc.bottom_radius = 0.12
		disc.height = 0.026
		disc.radial_segments = 24
		plate.mesh = disc
		var wood := StandardMaterial3D.new()
		wood.albedo_color = Color("30251c")
		wood.roughness = 0.98
		plate.material_override = wood
		slot.add_child(plate)
		var ring_node := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.093
		ring.outer_radius = 0.112
		ring.rings = 16
		ring.ring_segments = 6
		ring_node.mesh = ring
		ring_node.rotation.x = PI * 0.5
		ring_node.position.y = 0.018
		var brass := StandardMaterial3D.new()
		brass.albedo_color = Color("a98b51")
		brass.roughness = 1.0
		ring_node.material_override = brass
		slot.add_child(ring_node)
		var area := Area3D.new()
		area.name = "SlotRayPickArea"
		area.collision_layer = 16
		area.collision_mask = 0
		area.input_ray_pickable = false
		area.set_meta("slot_id", slot_id)
		var collision := CollisionShape3D.new()
		var cylinder_shape := CylinderShape3D.new()
		cylinder_shape.radius = 0.14
		cylinder_shape.height = 0.1
		collision.shape = cylinder_shape
		collision.position.y = 0.035
		area.add_child(collision)
		slot.add_child(area)
		slot_areas[slot_id] = area
		slot_meshes[slot_id] = slot


func _build_card_views() -> void:
	var player_centers := [0.110, 0.205, 0.300]
	for index in range(PLAYER_DEMOS.size()):
		var data: Dictionary = PLAYER_DEMOS[index]
		var card = CARD_VIEW_SCRIPT.new()
		card.name = "PlayerCard_" + data.id
		card.card_id = data.id
		card.title = data.title
		card.body = data.body
		card.atlas_texture = card_texture
		card.font = font
		card.textured_face = true
		add_child(card)
		card.place_held_from_screen(camera, player_centers[index], 0.92, 0.33, 4.8)
		card.rotation.z = [deg_to_rad(-14.0), 0.0, deg_to_rad(14.0)][index]
		player_cards.append(card)
		entry_start_positions["P%d" % index] = Vector3.ZERO
		entry_target_positions["P%d" % index] = card.global_position

	for index in range(3):
		var card = CARD_VIEW_SCRIPT.new()
		card.name = "OpponentCardBack_%d" % index
		card.card_id = "O_BACK_%d" % index
		card.title = ""
		card.body = ""
		card.atlas_texture = card_texture
		card.font = font
		card.textured_face = false
		card.face_up = false
		card.screen_height_fraction = 0.12
		card.screen_center_x = [0.34, 0.50, 0.66][index]
		card.screen_bottom_y = 0.365
		add_child(card)
		card.place_from_screen(composition, camera, card.screen_center_x, card.screen_bottom_y, card.screen_height_fraction)
		card.set_face_up(false)
		opponent_cards.append(card)

	var rule_card = CARD_VIEW_SCRIPT.new()
	rule_card.name = "RuleSummary3DCard"
	rule_card.card_id = "RULE"
	rule_card.title = "胜利规则"
	rule_card.body = "三名小队成员\n在桌上交战\n以公开战果决胜"
	rule_card.atlas_texture = card_texture
	rule_card.font = font
	add_child(rule_card)
	rule_card.place_from_screen(composition, camera, 0.085, 0.49, 0.145)
	var arena_card = CARD_VIEW_SCRIPT.new()
	arena_card.name = "ArenaSummary3DCard"
	arena_card.card_id = "ARENA"
	arena_card.title = "基础场地"
	arena_card.body = "同一张木桌\n中央战区保持\n本段仅舞台预览"
	arena_card.atlas_texture = card_texture
	arena_card.font = font
	add_child(arena_card)
	arena_card.place_from_screen(composition, camera, 0.085, 0.64, 0.145)

	for index in range(3):
		var public_card = CARD_VIEW_SCRIPT.new()
		public_card.name = "PublicEffectBack_%d" % index
		public_card.card_id = "PUBLIC_BACK_%d" % index
		public_card.textured_face = false
		public_card.atlas_texture = card_texture
		public_card.font = font
		public_card.screen_center_x = 0.90
		public_card.screen_bottom_y = [0.40, 0.50, 0.60][index]
		public_card.screen_height_fraction = 0.09
		public_card.face_up = false
		add_child(public_card)
		public_card.place_from_screen(composition, camera, public_card.screen_center_x, public_card.screen_bottom_y, public_card.screen_height_fraction)
		public_card.set_face_up(false)


func _build_chips() -> void:
	pot_tray = CHIP_STACK_SCRIPT.new()
	pot_tray.name = "PublicPotCopperTray3D"
	pot_tray.configure(1, 1, Color("694a31"), font, true)
	add_child(pot_tray)
	pot_tray.global_position = _world_at_screen(Vector2(0.79, 0.47), 0.04)

	for index in range(CHIP_DENOMINATIONS.size()):
		var player_stack = CHIP_STACK_SCRIPT.new()
		player_stack.name = "PlayerChipStack_%d" % CHIP_DENOMINATIONS[index]
		player_stack.configure(CHIP_DENOMINATIONS[index], [6, 5, 4, 3][index], CHIP_INKS[index], font)
		add_child(player_stack)
		var p_x := 0.845 + index * 0.035
		player_stack.global_position = _world_at_screen(Vector2(p_x, 0.80), 0.05)
		player_chip_stacks.append(player_stack)

		var opponent_stack = CHIP_STACK_SCRIPT.new()
		opponent_stack.name = "OpponentChipStack_%d" % CHIP_DENOMINATIONS[index]
		opponent_stack.configure(CHIP_DENOMINATIONS[index], [4, 3, 2, 1][index], CHIP_INKS[index], font)
		add_child(opponent_stack)
		var o_x := 0.22 + index * 0.038
		opponent_stack.global_position = _world_at_screen(Vector2(o_x, 0.27), 0.04)
		opponent_chip_stacks.append(opponent_stack)

	flying_chip = CHIP_STACK_SCRIPT.new()
	flying_chip.name = "DemoFlyingChips3D"
	flying_chip.configure(25, 2, CHIP_INKS[2], font)
	add_child(flying_chip)
	flying_chip.global_position = player_chip_stacks[2].global_position
	for stack in player_chip_stacks:
		stack.global_position = _world_at_screen(Vector2(0.98, 0.84), 0.04)
	for stack in opponent_chip_stacks:
		stack.global_position = _world_at_screen(Vector2(0.02, 0.26), 0.04)
	entry_start_positions["player_chips"] = _world_at_screen(Vector2(0.98, 0.84), 0.04)
	entry_target_positions["player_chips"] = _world_at_screen(Vector2(0.845, 0.80), 0.05)
	entry_start_positions["opponent_chips"] = _world_at_screen(Vector2(0.02, 0.26), 0.04)
	entry_target_positions["opponent_chips"] = _world_at_screen(Vector2(0.29, 0.25), 0.04)
	entry_start_positions["pot"] = _world_at_screen(Vector2(0.79, 0.47), 0.04)
	entry_target_positions["pot"] = pot_tray.global_position


func _build_player_hands() -> void:
	player_hands = HAND_RIG_SCRIPT.new()
	player_hands.name = "PlayerHandAtlasRig"
	player_hands.configure(camera, font)
	add_child(player_hands)
	var viewport_size := get_viewport().get_visible_rect().size
	var depth := 6.25
	var world_per_screen_pixel := (2.0 * depth * tan(deg_to_rad(camera.fov * 0.5))) / viewport_size.y
	player_hands.create_hand("left", "left_grip", composition, Vector2(0.045, 0.90), 0.19, world_per_screen_pixel, depth)
	player_hands.create_hand("right", "right_rest", composition, Vector2(0.76, 0.90), 0.17, world_per_screen_pixel, depth)


func _build_dealers() -> void:
	dealers = DEALER_RIG_SCRIPT.new()
	dealers.name = "DealerAtlasRigs"
	add_child(dealers)
	dealers.build_upper_body("player", composition, Vector2(0.075, 0.31), Vector2(0.155, 0.69), 0.23, false)
	dealers.build_upper_body("opponent", composition, Vector2(0.925, 0.29), Vector2(0.755, 0.39), 0.23, true)
	player_contact = dealers.get_contact_anchor("player")
	opponent_contact = dealers.get_contact_anchor("opponent")
	for side: String in ["player", "opponent"]:
		dealer_home_transforms[side] = dealers.dealer_nodes[side].global_transform
	for index in range(player_cards.size()):
		entry_start_positions["P%d" % index] = player_contact + camera.global_basis.y * (0.08 + index * 0.015)
	for index in range(opponent_cards.size()):
		entry_start_positions["O%d" % index] = opponent_contact + camera.global_basis.y * (0.08 + index * 0.015)
	for index in range(player_chip_stacks.size()):
		entry_start_positions["PC%d" % index] = player_contact + camera.global_basis.y * 0.11 + camera.global_basis.x * (0.018 * (index - 1.5))
		entry_start_positions["OC%d" % index] = opponent_contact + camera.global_basis.y * 0.11 + camera.global_basis.x * (0.018 * (index - 1.5))


func _build_entry_character_and_chair() -> void:
	opponent_entry = OPPONENT_ENTRY_SCRIPT.new()
	opponent_entry.name = "OpponentAC01AC03CroppedPoseRig"
	add_child(opponent_entry)
	opponent_entry.configure(camera, composition)
	var proxy: Node3D = composition.get_node_or_null("OpponentPoseProxyAnchor")
	if proxy != null:
		proxy.visible = false
	entry_chair = Node3D.new()
	entry_chair.name = "AC02PhysicalChairProxy"
	var size := get_viewport().get_visible_rect().size
	var chair_pixel := Vector2(0.515 * size.x, 0.355 * size.y)
	var chair_ray_origin := camera.project_ray_origin(chair_pixel)
	entry_chair.global_transform = Transform3D(camera.global_basis.orthonormalized(), chair_ray_origin + camera.project_ray_normal(chair_pixel) * 17.7)
	entry_chair.scale = Vector3.ONE * 3.3
	add_child(entry_chair)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("725235")
	wood.roughness = 0.96
	_add_chair_piece("Seat", Vector3(0.0, 0.19, 0.0), Vector3(0.48, 0.065, 0.42), wood)
	_add_chair_piece("BackLeftPost", Vector3(-0.205, 0.45, -0.18), Vector3(0.055, 0.50, 0.075), wood)
	_add_chair_piece("BackRightPost", Vector3(0.205, 0.45, -0.18), Vector3(0.055, 0.50, 0.075), wood)
	_add_chair_piece("BackTopRail", Vector3(0.0, 0.685, -0.18), Vector3(0.43, 0.065, 0.075), wood)
	_add_chair_piece("BackMiddleRail", Vector3(0.0, 0.43, -0.18), Vector3(0.37, 0.055, 0.075), wood)
	_add_chair_piece("BackLowerRail", Vector3(0.0, 0.235, -0.18), Vector3(0.38, 0.045, 0.075), wood)
	for x in [-0.19, 0.19]:
		for z in [-0.15, 0.15]:
			_add_chair_piece("Leg_%s_%s" % [str(x), str(z)], Vector3(x, 0.095, z), Vector3(0.055, 0.19, 0.055), wood)


func _add_chair_piece(piece_name: String, center: Vector3, dimensions: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = piece_name
	var box := BoxMesh.new()
	box.size = dimensions
	box.material = material
	part.mesh = box
	part.position = center
	entry_chair.add_child(part)


func _world_at_screen(normalized: Vector2, world_height: float) -> Vector3:
	return composition._world_at_screen_point(normalized, world_height)


func _build_stage_ui() -> void:
	ui_layer = CanvasLayer.new()
	ui_layer.name = "StageControlsLayer"
	ui_layer.layer = 25
	add_child(ui_layer)
	ui_root = Control.new()
	ui_root.name = "StagePaperUI"
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_PASS
	ui_root.theme = Theme.new()
	ui_root.theme.default_font = font
	ui_root.theme.default_font_size = 24
	ui_layer.add_child(ui_root)

	var dev_ribbon := Label.new()
	dev_ribbon.name = "DeveloperWatermark"
	dev_ribbon.text = "七罪暗队 · 可玩版 / 真实对局状态 · 组队、下注、配置、战斗与结算"
	dev_ribbon.position = Vector2(24, 12)
	dev_ribbon.size = Vector2(920, 44)
	dev_ribbon.add_theme_font_size_override("font_size", 24)
	dev_ribbon.add_theme_color_override("font_color", Color("e4d8bc"))
	dev_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(dev_ribbon)
	title_banner = dev_ribbon

	status_label = Label.new()
	status_label.name = "StageStatus"
	status_label.position = Vector2(24, 60)
	status_label.size = Vector2(880, 50)
	status_label.text = "组队完成后进入真实下注与配置；下方动作预览仅用于牌桌交互检查。"
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", Color("e4d8bc"))
	status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(status_label)

	readout_label = Label.new()
	readout_label.name = "SelectionReadout"
	readout_label.position = Vector2(440, 872)
	readout_label.size = Vector2(1280, 92)
	readout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	readout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readout_label.add_theme_font_size_override("font_size", 28)
	readout_label.add_theme_color_override("font_color", Color("241d16"))
	readout_label.visible = false
	readout_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_root.add_child(readout_label)

	var paper_strip := PanelContainer.new()
	paper_strip.name = "DebugWoodControlStrip"
	paper_strip.position = Vector2(14, 1006)
	paper_strip.size = Vector2(1892, 60)
	var paper_style := StyleBoxFlat.new()
	paper_style.bg_color = Color("241c15")
	paper_style.border_color = Color("9a794a")
	paper_style.set_border_width_all(2)
	paper_style.set_corner_radius_all(0)
	paper_style.set_content_margin_all(7)
	paper_strip.add_theme_stylebox_override("panel", paper_style)
	ui_root.add_child(paper_strip)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	paper_strip.add_child(row)
	var dev_label := Label.new()
	dev_label.text = "开发动作"
	dev_label.add_theme_font_size_override("font_size", 23)
	dev_label.add_theme_color_override("font_color", Color("dfcda8"))
	row.add_child(dev_label)

	action_select = OptionButton.new()
	action_select.custom_minimum_size = Vector2(345, 42)
	for action: Array in ACTIONS:
		action_select.add_item(action[1], action[0])
	row.add_child(action_select)
	action_play_button = Button.new()
	action_play_button.text = "播放动作"
	action_play_button.custom_minimum_size = Vector2(150, 42)
	action_play_button.pressed.connect(_play_selected_action)
	row.add_child(action_play_button)
	entry_play_button = Button.new()
	entry_play_button.text = "播放4.8秒入场段"
	entry_play_button.custom_minimum_size = Vector2(220, 42)
	entry_play_button.pressed.connect(_play_entry_timeline)
	row.add_child(entry_play_button)
	entry_slider = HSlider.new()
	entry_slider.min_value = 0.0
	entry_slider.max_value = 4.8
	entry_slider.step = 0.01
	entry_slider.custom_minimum_size = Vector2(430, 42)
	entry_slider.value_changed.connect(_on_entry_slider_changed)
	row.add_child(entry_slider)
	entry_time_label = Label.new()
	entry_time_label.text = "4.80 / 4.80 秒"
	entry_time_label.custom_minimum_size = Vector2(170, 42)
	entry_time_label.add_theme_font_size_override("font_size", 22)
	entry_time_label.add_theme_color_override("font_color", Color("dfcda8"))
	row.add_child(entry_time_label)
	slot_select = OptionButton.new()
	slot_select.custom_minimum_size = Vector2(190, 42)
	for index in range(6):
		var label := "%d号%s槽" % [index / 2 + 1, "装备" if index % 2 == 0 else "效果"]
		slot_select.add_item(label, index)
	row.add_child(slot_select)
	install_button = Button.new()
	install_button.text = "安装所选卡"
	install_button.custom_minimum_size = Vector2(160, 42)
	install_button.pressed.connect(_install_selected_card)
	row.add_child(install_button)
	if not OS.is_debug_build() and not Engine.is_editor_hint():
		paper_strip.visible = false
		dev_ribbon.visible = false

	for slot_id: String in SLOT_IDS:
		var slot_label := Label.new()
		slot_label.name = "SlotLabel_" + slot_id
		slot_label.text = "装" if slot_id.ends_with("EQ") else "效"
		slot_label.add_theme_font_size_override("font_size", 18)
		slot_label.add_theme_color_override("font_color", Color("eadbb7"))
		slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_root.add_child(slot_label)
		slot_labels[slot_id] = slot_label

	for pair in [["玩家演示额", Vector2(0.83, 0.68)], ["对手演示额", Vector2(0.28, 0.16)], ["奖池演示额", Vector2(0.79, 0.43)]]:
		var amount_label := Label.new()
		amount_label.text = pair[0]
		amount_label.add_theme_font_size_override("font_size", 22)
		amount_label.add_theme_color_override("font_color", Color("eadbb7"))
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ui_root.add_child(amount_label)
		amount_labels[pair[0]] = amount_label

	_on_viewport_resized()


func _load_character_names() -> void:
	var file := FileAccess.open("res://content/characters/characters.json", FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	for definition: Variant in parsed.get("characters", []):
		if definition is Dictionary:
			character_names[str(definition.get("id", ""))] = str(definition.get("name", ""))


func _load_content_details() -> void:
	character_details.clear()
	attachment_details.clear()
	environment_details.clear()
	rule_details.clear()
	content_detail_catalog = CONTENT_DETAILS_SCRIPT.new()
	content_detail_catalog.load_catalog()
	for content_id: String in content_detail_catalog.entries:
		var entry: Dictionary = content_detail_catalog.entries[content_id]
		var category := str(entry.get("category", ""))
		if category in ["WR", "GR", "GL", "EN", "SL", "LU", "PR"]:
			character_details[content_id] = entry
		elif category in ["EQ", "FX"]:
			attachment_details[content_id] = entry
		elif category in ["AR", "PE"]:
			environment_details[content_id] = entry
		elif category == "VC":
			rule_details[content_id] = entry


func _build_hover_detail_ui() -> void:
	hover_detail_panel = PanelContainer.new()
	hover_detail_panel.name = "ContentHoverDetail"
	hover_detail_panel.position = Vector2(750, 112)
	hover_detail_panel.size = Vector2(550, 650)
	hover_detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_detail_panel.visible = false
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.045, 0.032, 0.024, 0.97)
	panel_style.border_color = Color("d2ad68")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(18)
	hover_detail_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(hover_detail_panel)
	hover_detail_label = Label.new()
	hover_detail_label.name = "ContentHoverDetailText"
	hover_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hover_detail_label.add_theme_font_size_override("font_size", 20)
	hover_detail_label.add_theme_color_override("font_color", Color("f0dfbd"))
	hover_detail_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hover_detail_panel.add_child(hover_detail_label)


func _show_content_detail(content_id: String, owner: String = "ui") -> void:
	if hover_detail_panel == null or hover_detail_label == null or content_detail_catalog == null:
		return
	var text := content_detail_catalog.detail_text(content_id)
	if text.is_empty():
		return
	hovered_detail_id = content_id
	hovered_detail_owner = owner
	hover_detail_label.text = text
	hover_detail_panel.visible = true


func _show_content_details(content_ids: Array, heading: String, owner: String = "ui") -> void:
	if hover_detail_panel == null or hover_detail_label == null or content_detail_catalog == null:
		return
	var text := content_detail_catalog.combined_text(content_ids, heading)
	if text.is_empty():
		return
	hovered_detail_id = "|".join(content_ids)
	hovered_detail_owner = owner
	hover_detail_label.text = text
	hover_detail_panel.visible = true


func _hide_content_detail(owner: String = "ui") -> void:
	if owner != hovered_detail_owner:
		return
	hovered_detail_id = ""
	hovered_detail_owner = ""
	if hover_detail_panel != null:
		hover_detail_panel.visible = false


func _show_team_candidate_detail(slot: int, index: int) -> void:
	if game_controller == null:
		return
	var candidates: Array = game_controller.observation("player").get("your_private", {}).get("team_candidates", {}).get(str(slot), [])
	if index >= 0 and index < candidates.size():
		_show_content_detail(str(candidates[index]), "candidate")


func _show_game_context_details() -> void:
	if game_controller == null:
		return
	var observed := game_controller.observation("player")
	var public_view: Dictionary = observed.get("public", {})
	var ids: Array = [str(public_view.get("rule_id", "")), str(public_view.get("arena_id", ""))]
	for member: Variant in observed.get("your_private", {}).get("team", []):
		if member is Dictionary: ids.append(str(member.get("definition_id", "")))
	for effect: Variant in public_view.get("revealed_effects", []):
		ids.append(str(effect.get("id", "")) if effect is Dictionary else str(effect))
	var current_effect := str(public_view.get("current_public_effect", ""))
	if not current_effect.is_empty(): ids.append(current_effect)
	_show_content_details(ids, "当前规则、场地、己方队伍与公开效果", "context")


func _build_team_selection_ui() -> void:
	team_panel = PanelContainer.new()
	team_panel.name = "TeamSelectionPanel"
	team_panel.position = Vector2(1040, 112)
	team_panel.size = Vector2(820, 610)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.065, 0.045, 0.96)
	panel_style.border_color = Color("b99a61")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(18)
	team_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(team_panel)

	var column := VBoxContainer.new()
	column.name = "TeamSelectionColumn"
	column.add_theme_constant_override("separation", 10)
	team_panel.add_child(column)
	var title := Label.new()
	title.text = "暗队组建 · 每个位置三选一"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("f1dfb5"))
	column.add_child(title)
	team_status_label = Label.new()
	team_status_label.name = "TeamSelectionStatus"
	team_status_label.text = "每个位置可重抽一次；被换掉的候选不会回池。"
	team_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	team_status_label.custom_minimum_size = Vector2(0, 54)
	team_status_label.add_theme_font_size_override("font_size", 22)
	team_status_label.add_theme_color_override("font_color", Color("ddc99e"))
	column.add_child(team_status_label)
	for slot in [1, 2, 3]:
		var row_panel := PanelContainer.new()
		row_panel.name = "TeamSlot%d" % slot
		var row_style := StyleBoxFlat.new()
		row_style.bg_color = Color(0.15, 0.11, 0.075, 0.82)
		row_style.border_color = Color("765c39")
		row_style.set_border_width_all(1)
		row_style.set_corner_radius_all(5)
		row_style.set_content_margin_all(8)
		row_panel.add_theme_stylebox_override("panel", row_style)
		column.add_child(row_panel)
		var row := HBoxContainer.new()
		row.name = "Candidates"
		row.add_theme_constant_override("separation", 8)
		row_panel.add_child(row)
		var slot_label := Label.new()
		slot_label.text = "位置 %d" % slot
		slot_label.custom_minimum_size = Vector2(90, 52)
		slot_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		slot_label.add_theme_font_size_override("font_size", 22)
		slot_label.add_theme_color_override("font_color", Color("e5d0a8"))
		row.add_child(slot_label)
		var button_list: Array[Button] = []
		for index in range(3):
			var candidate_button := Button.new()
			candidate_button.name = "Candidate%d" % index
			candidate_button.custom_minimum_size = Vector2(175, 58)
			candidate_button.add_theme_font_size_override("font_size", 18)
			candidate_button.pressed.connect(_on_team_candidate_pressed.bind(slot, index))
			candidate_button.mouse_entered.connect(_show_team_candidate_detail.bind(slot, index))
			candidate_button.mouse_exited.connect(_hide_content_detail.bind("candidate"))
			row.add_child(candidate_button)
			button_list.append(candidate_button)
		team_choice_buttons[slot] = button_list
		var reroll_button := Button.new()
		reroll_button.name = "Reroll"
		reroll_button.text = "重抽一次"
		reroll_button.custom_minimum_size = Vector2(130, 58)
		reroll_button.add_theme_font_size_override("font_size", 18)
		reroll_button.pressed.connect(_on_team_reroll_pressed.bind(slot))
		row.add_child(reroll_button)
		team_reroll_buttons[slot] = reroll_button


func _next_team_command_id() -> String:
	team_command_serial += 1
	return "table-team-selection-%d" % team_command_serial


func _on_team_candidate_pressed(slot: int, index: int) -> void:
	if game_session == null or game_controller == null or game_session.state.phase != "TEAM_SELECTION":
		return
	var observed := game_controller.observation("player")
	var candidates: Array = observed.get("your_private", {}).get("team_candidates", {}).get(str(slot), [])
	if index < 0 or index >= candidates.size():
		return
	var command := COMMAND_SCRIPT.new(_next_team_command_id(), "player", "choose_character",
		{"slot": slot, "character_id": str(candidates[index])}, int(game_session.state.revision))
	var result: Dictionary = game_controller.submit(command)
	if not bool(result.get("accepted", false)):
		team_status_label.text = "选择未提交：%s" % str(result.get("reason", result.get("error", "未知错误")))
		return
	_update_team_selection_ui()
	_auto_select_opponent_team_if_ready()
	_refresh_game_loop_ui(true)


func _on_team_reroll_pressed(slot: int) -> void:
	if game_session == null or game_controller == null or game_session.state.phase != "TEAM_SELECTION":
		return
	var command := COMMAND_SCRIPT.new(_next_team_command_id(), "player", "reroll_character",
		{"slot": slot}, int(game_session.state.revision))
	var result: Dictionary = game_controller.submit(command)
	if not bool(result.get("accepted", false)):
		team_status_label.text = "该位置不能再重抽：%s" % str(result.get("reason", result.get("error", "未知错误")))
		return
	_update_team_selection_ui()


func _auto_select_opponent_team_if_ready() -> void:
	if game_session == null or game_controller == null or game_session.state.phase != "TEAM_SELECTION":
		return
	var player_private: Dictionary = game_controller.observation("player").get("your_private", {})
	var player_selected: Dictionary = player_private.get("team_selection", {})
	if player_selected.size() < 3:
		return
	for slot in [1, 2, 3]:
		var opponent_view := game_controller.observation("opponent")
		var opponent_private: Dictionary = opponent_view.get("your_private", {})
		var selected: Dictionary = opponent_private.get("team_selection", {})
		if selected.has(str(slot)):
			continue
		var candidates: Array = opponent_private.get("team_candidates", {}).get(str(slot), [])
		if candidates.is_empty():
			return
		var command := COMMAND_SCRIPT.new(_next_team_command_id(), "opponent", "choose_character",
			{"slot": slot, "character_id": str(candidates[0])}, int(game_session.state.revision))
		game_controller.submit(command)
	_update_team_selection_ui()
	_refresh_game_loop_ui(true)


func _update_team_selection_ui() -> void:
	if team_panel == null or game_controller == null:
		return
	var active: bool = game_session != null and game_session.state.phase == "TEAM_SELECTION"
	team_panel.visible = active
	if not active:
		if team_status_label != null:
			team_status_label.text = "组队完成；已进入原有下注与装备流程。"
		return
	var observed := game_controller.observation("player")
	var private_view: Dictionary = observed.get("your_private", {})
	var candidates: Dictionary = private_view.get("team_candidates", {})
	var selected: Dictionary = private_view.get("team_selection", {})
	var rerolls: Dictionary = private_view.get("team_rerolls", {})
	for slot in [1, 2, 3]:
		var list: Array = candidates.get(str(slot), [])
		var buttons: Array = team_choice_buttons.get(slot, [])
		var already_selected := selected.has(str(slot))
		for index in range(buttons.size()):
			var button: Button = buttons[index]
			if index < list.size():
				var id := str(list[index])
				var display_name := str(character_names.get(id, ""))
				button.text = "%s\n%s" % [id, display_name] if not display_name.is_empty() else id
				button.tooltip_text = id
				button.disabled = already_selected
				button.modulate = Color("789a72") if already_selected else Color.WHITE
			else:
				button.text = "—"
				button.disabled = true
		var reroll_button: Button = team_reroll_buttons.get(slot)
		if reroll_button != null:
			reroll_button.disabled = already_selected or bool(rerolls.get(str(slot), false))
	var done_count := selected.size()
	team_status_label.text = "已选 %d/3；对手候选私有。每个位置最多重抽一次。" % done_count


func _build_game_loop_ui() -> void:
	game_panel = PanelContainer.new()
	game_panel.name = "PlayableGamePanel"
	game_panel.position = Vector2(1070, 92)
	game_panel.size = Vector2(760, 820)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.075, 0.052, 0.035, 0.96)
	panel_style.border_color = Color("b99a61")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(18)
	game_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(game_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	game_panel.add_child(column)
	var title := Label.new()
	title.text = "七罪暗队 · 当前对局"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color("f1dfb5"))
	column.add_child(title)
	game_phase_label = Label.new()
	game_phase_label.name = "GamePhase"
	game_phase_label.add_theme_font_size_override("font_size", 24)
	game_phase_label.add_theme_color_override("font_color", Color("e8d4aa"))
	column.add_child(game_phase_label)
	game_context_label = Label.new()
	game_context_label.name = "GameContext"
	game_context_label.custom_minimum_size = Vector2(0, 176)
	game_context_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	game_context_label.add_theme_font_size_override("font_size", 20)
	game_context_label.add_theme_color_override("font_color", Color("d8c49c"))
	game_context_label.mouse_filter = Control.MOUSE_FILTER_STOP
	game_context_label.mouse_entered.connect(_show_game_context_details)
	game_context_label.mouse_exited.connect(_hide_content_detail.bind("context"))
	column.add_child(game_context_label)
	var slot_row := HBoxContainer.new()
	var slot_caption := Label.new()
	slot_caption.text = "装备/效果安装位置"
	slot_caption.add_theme_font_size_override("font_size", 19)
	slot_row.add_child(slot_caption)
	draft_slot_select = OptionButton.new()
	draft_slot_select.name = "DraftExternalSlot"
	draft_slot_select.custom_minimum_size = Vector2(250, 42)
	for external_slot in [1, 2, 3]:
		draft_slot_select.add_item("%d号人物槽" % external_slot, external_slot)
	draft_slot_select.item_selected.connect(func(_index: int) -> void:
		game_ui_signature = ""
		_refresh_game_loop_ui(true)
	)
	slot_row.add_child(draft_slot_select)
	column.add_child(slot_row)
	var separator := HSeparator.new()
	column.add_child(separator)
	game_action_box = VBoxContainer.new()
	game_action_box.name = "LegalActionButtons"
	game_action_box.add_theme_constant_override("separation", 7)
	column.add_child(game_action_box)


func _build_quick_tutorial_ui() -> void:
	tutorial_toggle_button = Button.new()
	tutorial_toggle_button.name = "TutorialToggle"
	tutorial_toggle_button.text = "关闭新手引导" if tutorial_enabled else "重看新手引导"
	tutorial_toggle_button.position = Vector2(1640, 18)
	tutorial_toggle_button.size = Vector2(230, 46)
	tutorial_toggle_button.add_theme_font_size_override("font_size", 20)
	tutorial_toggle_button.pressed.connect(_toggle_quick_tutorial)
	ui_root.add_child(tutorial_toggle_button)

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "QuickTutorialPanel"
	tutorial_panel.position = Vector2(24, 116)
	tutorial_panel.size = Vector2(720, 220)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.065, 0.045, 0.03, 0.94)
	panel_style.border_color = Color("d2ad68")
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(16)
	tutorial_panel.add_theme_stylebox_override("panel", panel_style)
	ui_root.add_child(tutorial_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	tutorial_panel.add_child(column)
	tutorial_title_label = Label.new()
	tutorial_title_label.name = "TutorialStepTitle"
	tutorial_title_label.add_theme_font_size_override("font_size", 27)
	tutorial_title_label.add_theme_color_override("font_color", Color("f4d99e"))
	column.add_child(tutorial_title_label)
	tutorial_body_label = Label.new()
	tutorial_body_label.name = "TutorialStepBody"
	tutorial_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_body_label.custom_minimum_size = Vector2(670, 125)
	tutorial_body_label.add_theme_font_size_override("font_size", 21)
	tutorial_body_label.add_theme_color_override("font_color", Color("e5d5b5"))
	column.add_child(tutorial_body_label)
	_update_quick_tutorial(true)
	tutorial_panel.visible = tutorial_enabled


func _toggle_quick_tutorial() -> void:
	tutorial_enabled = not tutorial_enabled
	tutorial_panel.visible = tutorial_enabled
	tutorial_toggle_button.text = "关闭新手引导" if tutorial_enabled else ("重看新手引导" if tutorial_completed_persisted else "打开新手引导")
	if tutorial_enabled:
		tutorial_ui_signature = ""
		_update_quick_tutorial(true)


func _is_tutorial_completed() -> bool:
	if not FileAccess.file_exists(TUTORIAL_COMPLETION_PATH):
		return false
	var file := FileAccess.open(TUTORIAL_COMPLETION_PATH, FileAccess.READ)
	if file == null:
		return false
	return file.get_as_text().strip_edges() == "completed"


func _mark_tutorial_completed() -> void:
	if tutorial_completed_persisted:
		return
	var file := FileAccess.open(TUTORIAL_COMPLETION_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("completed")
	tutorial_completed_persisted = true
	tutorial_enabled = false
	if tutorial_panel != null:
		tutorial_panel.visible = false
	if tutorial_toggle_button != null:
		tutorial_toggle_button.text = "重看新手引导"


func _maybe_complete_first_table_tutorial() -> void:
	if tutorial_completed_persisted or game_session == null:
		return
	var phase := str(game_session.state.phase)
	if tutorial_last_phase != "SETTLED" and phase == "SETTLED":
		_mark_tutorial_completed()
	tutorial_last_phase = phase


func _update_quick_tutorial(force: bool = false) -> void:
	if tutorial_panel == null or tutorial_title_label == null or game_controller == null or game_session == null:
		return
	if not tutorial_enabled:
		return
	var phase := str(game_session.state.phase)
	var observation := game_controller.observation("player")
	var selected_count := int(observation.get("your_private", {}).get("team_selection", {}).size())
	var revision := int(observation.get("revision", -1))
	var signature := "%s|%d|%d" % [phase, revision, selected_count]
	if not force and tutorial_ui_signature == signature:
		return
	tutorial_ui_signature = signature
	match phase:
		"TEAM_SELECTION":
			tutorial_title_label.text = "新手引导 1/6 · 组建三人暗队"
			tutorial_body_label.text = "每个位置从三名候选中选一名（当前 %d/3）。不满意可先点“重抽一次”；换掉的三名不会再回来。将鼠标移到候选上可看人物能力。" % selected_count
		"BETTING":
			tutorial_title_label.text = "新手引导 2/6 · 看懂信息并下注"
			tutorial_body_label.text = "先把鼠标移到人物、规则或场地名称上查看完整说明。确认后，在右侧选择过牌、下注、跟注或弃牌；按钮上的数字就是本次实际支付额。"
		"OPERATION_COMMIT":
			tutorial_title_label.text = "新手引导 3/6 · 选择本轮配置"
			tutorial_body_label.text = "右侧列出的都是当前真实可用操作。你可以不调整，也可以付费抽取装备/效果、移动已装卡，或确认主攻方向。槽位规则与正式对局一致。"
		"DRAFT_SELECTION":
			tutorial_title_label.text = "新手引导 4/6 · 三选一并安装"
			tutorial_body_label.text = "把鼠标移到三张候选卡上查看详细效果；先选右侧的安装人物槽，再点击其中一张。选定后会真实装入对应的装备槽或效果槽。"
		"PUBLIC_COMMIT", "PUBLIC_BID":
			tutorial_title_label.text = "新手引导 4/6 · 处理公开效果"
			tutorial_body_label.text = "公开效果会同时影响牌桌双方。选择是否启用；若双方意见不同，按右侧按钮进行竞价或放弃，随后进入战斗。"
		"BATTLE_READY", "BATTLE_REPLAY":
			tutorial_title_label.text = "新手引导 5/6 · 战斗"
			tutorial_body_label.text = "配置已经锁定。系统正按人物、装备、效果、场地和主攻方向自动结算；回放消费完成后会自动显示最终结果。"
		"SETTLED":
			tutorial_title_label.text = "新手引导 6/6 · 结算"
			tutorial_body_label.text = "本手已结束。右侧会显示胜负、原因和筹码变化。点击“开始下一手”继续使用当前桌上筹码，或点击“带筹码离桌”结束。"
		_:
			tutorial_title_label.text = "新手引导 · 当前阶段"
			tutorial_body_label.text = "按照右侧当前合法操作继续；引导会随真实对局阶段自动更新，不会替你提交操作。"


func _next_game_command_id(side: String) -> String:
	game_command_serial += 1
	return "table-game-%s-%d" % [side, game_command_serial]


func _clear_game_action_buttons() -> void:
	if game_action_box == null:
		return
	for child in game_action_box.get_children():
		game_action_box.remove_child(child)
		child.queue_free()


func _refresh_game_loop_ui(force: bool = false) -> void:
	if game_panel == null or game_controller == null or game_session == null:
		return
	_update_quick_tutorial(force)
	var observation := game_controller.observation("player")
	var phase := str(observation.get("phase", ""))
	game_panel.visible = phase != "TEAM_SELECTION"
	if phase == "TEAM_SELECTION":
		return
	var public_view: Dictionary = observation.get("public", {})
	var balances: Dictionary = public_view.get("balances", {})
	var actions: Array[Dictionary] = game_controller.legal_actions("player")
	var signature := "%s|%s|%s|%s" % [phase, int(observation.get("revision", -1)), JSON.stringify(actions), draft_slot_select.get_selected_id()]
	if not force and signature == game_ui_signature:
		return
	game_ui_signature = signature
	game_phase_label.text = "阶段：%s · 第 %d 手 / 第 %d 轮" % [_phase_display_name(phase), int(public_view.get("hand_id", 0)), int(observation.get("round", 0))]
	var own_team: Array = observation.get("your_private", {}).get("team", [])
	var team_ids: Array[String] = []
	for member: Variant in own_team:
		if member is Dictionary:
			team_ids.append(str(member.get("definition_id", "")))
	var result: Dictionary = public_view.get("battle_result", {})
	var result_line := ""
	if not result.is_empty():
		result_line = "\n结算：%s（%s）" % [_winner_display(str(result.get("winner", ""))), str(result.get("reason", ""))]
	game_context_label.text = "玩家筹码 %d · 对手筹码 %d · 奖池 %d\n胜利规则 %s · 场地 %s\n己方暗队 %s\n公开效果 %s%s%s" % [
		int(balances.get("player_table", 0)), int(balances.get("opponent_table", 0)), int(balances.get("pot", 0)),
		str(public_view.get("rule_id", "—")), str(public_view.get("arena_id", "—")),
		" / ".join(team_ids) if not team_ids.is_empty() else "组建中",
		_summarize_public_effects(public_view.get("revealed_effects", [])),
		result_line, ("\n" + replay_notice) if not replay_notice.is_empty() else ""]
	_clear_game_action_buttons()
	if phase == "BATTLE_REPLAY":
		_add_game_info("战斗回放结算中……")
		return
	if actions.is_empty():
		_add_game_info("等待对手行动……" if phase != "SETTLED" else "本局已结束。")
		return
	for action: Dictionary in actions:
		if str(action.get("type", "")) == "choose_draft_card":
			for card_id: Variant in action.get("offer", []):
				var expanded := action.duplicate(true)
				expanded["selected_card_id"] = str(card_id)
				_add_game_action_button("安装 %s 到 %d号槽" % [str(card_id), draft_slot_select.get_selected_id()], expanded)
		else:
			_add_game_action_button(_game_action_label(action), action)


func _add_game_info(message: String) -> void:
	var label := Label.new()
	label.text = message
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color("c8b58f"))
	game_action_box.add_child(label)


func _add_game_action_button(label: String, action: Dictionary) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0, 48)
	button.add_theme_font_size_override("font_size", 20)
	button.disabled = not _action_has_default_payload("player", action)
	button.pressed.connect(_on_game_action_pressed.bind(action.duplicate(true)))
	var detail_id := str(action.get("selected_card_id", ""))
	if detail_id.is_empty() and str(action.get("type", "")) in ["public_decision", "public_bid", "pass_public_bid"]:
		detail_id = str(game_controller.observation("player").get("public", {}).get("current_public_effect", ""))
	if not detail_id.is_empty():
		button.tooltip_text = content_detail_catalog.detail_text(detail_id) if content_detail_catalog != null else detail_id
		button.mouse_entered.connect(_show_content_detail.bind(detail_id, "action"))
		button.mouse_exited.connect(_hide_content_detail.bind("action"))
	game_action_box.add_child(button)


func _on_game_action_pressed(action: Dictionary) -> void:
	_submit_game_action("player", action)


func _submit_game_action(side: String, action: Dictionary) -> Dictionary:
	var payload: Variant = _default_action_payload(side, action)
	if payload == null:
		return {"accepted": false, "reason": "该操作当前没有有效目标"}
	var command := COMMAND_SCRIPT.new(_next_game_command_id(side), side, str(action.get("type", "")), payload, int(game_session.state.revision))
	var result: Dictionary = game_controller.submit(command)
	if not bool(result.get("accepted", false)):
		replay_notice = "操作未接受：%s" % str(result.get("reason", result.get("error", "未知错误")))
	else:
		replay_notice = "已执行：%s" % _game_action_label(action)
	game_ui_signature = ""
	_update_team_selection_ui()
	_refresh_game_loop_ui(true)
	_maybe_complete_first_table_tutorial()
	automatic_action_cooldown = 0.12
	return result


func _default_action_payload(side: String, action: Dictionary) -> Variant:
	var action_type := str(action.get("type", ""))
	match action_type:
		"bet", "raise", "public_bid":
			if int(action.get("amount_min", 0)) > int(action.get("amount_max", -1)):
				return null
			return {"amount": int(action.get("amount_min", 0))}
		"call":
			var call_payload := {"amount": int(action.get("amount_min", 0))}
			if bool(action.get("short_stack_all_in", false)):
				call_payload["all_in"] = true
			return call_payload
		"commit_operation":
			var operation := str(action.get("operation", "pass"))
			if operation == "set_arrows":
				return {"operation": operation, "arrows": [1, 2, 3]}
			if operation == "move_card":
				return _default_move_payload(side)
			return {"operation": operation}
		"public_decision":
			return {"activate": bool(action.get("activate", false))}
		"choose_draft_card":
			var card_id := str(action.get("selected_card_id", ""))
			if card_id.is_empty():
				var offer: Array = action.get("offer", [])
				if offer.is_empty():
					return null
				card_id = str(offer[0])
			var slot := draft_slot_select.get_selected_id() if side == "player" and draft_slot_select != null else _first_available_external_slot(side, card_id)
			return {"card_id": card_id, "slot": slot, "slot_kind": "equipment" if card_id.begins_with("EQ") else "effect"}
		"choose_character":
			var candidates: Array = action.get("candidates", [])
			if candidates.is_empty(): return null
			return {"slot": int(action.get("slot", 0)), "character_id": str(candidates[0])}
		"reroll_character":
			return {"slot": int(action.get("slot", 0))}
		_:
			return {}


func _action_has_default_payload(side: String, action: Dictionary) -> bool:
	return _default_action_payload(side, action) != null


func _default_move_payload(side: String) -> Variant:
	var observed := game_controller.observation(side)
	var installed: Array = observed.get("your_private", {}).get("installed_cards", [])
	while installed.size() < 6:
		installed.append("")
	for kind: String in ["equipment", "effect"]:
		var offset := 0 if kind == "equipment" else 3
		for source in range(3):
			if str(installed[offset + source]).is_empty(): continue
			for target in range(3):
				if target != source:
					return {"operation": "move_card", "from": source + 1, "to": target + 1, "slot_kind": kind}
	return null


func _first_available_external_slot(side: String, card_id: String) -> int:
	var installed: Array = game_controller.observation(side).get("your_private", {}).get("installed_cards", [])
	var offset := 0 if card_id.begins_with("EQ") else 3
	for index in range(3):
		if installed.size() <= offset + index or str(installed[offset + index]).is_empty():
			return index + 1
	return 1


func _drive_opponent_once() -> bool:
	if game_controller == null or game_controller.pending_battle_replay:
		return false
	var actions: Array[Dictionary] = game_controller.legal_actions("opponent")
	if actions.is_empty():
		return false
	var preferred_types := ["call", "check", "commit_operation", "choose_draft_card", "public_decision", "pass_public_bid", "all_in", "fold"]
	for preferred: String in preferred_types:
		for action: Dictionary in actions:
			if str(action.get("type", "")) != preferred: continue
			if preferred == "commit_operation" and str(action.get("operation", "")) != "pass": continue
			if preferred == "public_decision" and bool(action.get("activate", true)): continue
			if not _action_has_default_payload("opponent", action): continue
			_submit_game_action("opponent", action)
			return true
	return false


func _finish_pending_battle_replay() -> bool:
	if game_controller == null or not game_controller.pending_battle_replay:
		return false
	var replay := game_controller.pending_battle_replay_package()
	var event_count := int(replay.get("event_count", -1))
	var result := game_controller.finish_battle_replay(event_count)
	replay_notice = "战斗回放已消费 %d 个事件。" % event_count if bool(result.get("accepted", false)) else "战斗结算失败：%s" % str(result.get("error", "未知错误"))
	game_ui_signature = ""
	_refresh_game_loop_ui(true)
	_maybe_complete_first_table_tutorial()
	return bool(result.get("accepted", false))


func advance_playable_smoke_once() -> bool:
	if game_session.state.phase == "TEAM_SELECTION":
		for slot in [1, 2, 3]:
			var selected: Dictionary = game_controller.observation("player").get("your_private", {}).get("team_selection", {})
			if not selected.has(str(slot)):
				_on_team_candidate_pressed(slot, 0)
				return true
		return false
	if game_controller.pending_battle_replay:
		return _finish_pending_battle_replay()
	if _drive_opponent_once():
		return true
	var actions: Array[Dictionary] = game_controller.legal_actions("player")
	var preferred_types := ["check", "commit_operation", "choose_draft_card", "public_decision", "pass_public_bid", "call", "all_in"]
	for preferred: String in preferred_types:
		for action: Dictionary in actions:
			if str(action.get("type", "")) != preferred: continue
			if preferred == "commit_operation" and str(action.get("operation", "")) != "pass": continue
			if preferred == "public_decision" and bool(action.get("activate", true)): continue
			if not _action_has_default_payload("player", action): continue
			_submit_game_action("player", action)
			return true
	return false


func _game_action_label(action: Dictionary) -> String:
	match str(action.get("type", "")):
		"check": return "过牌"
		"bet": return "下注 %d" % int(action.get("amount_min", 0))
		"raise": return "加注至 %d" % int(action.get("amount_min", 0))
		"call": return "跟注 %d" % int(action.get("amount_min", 0))
		"all_in": return "全押 %d" % int(action.get("amount_min", 0))
		"fold": return "弃牌（输掉本手投入）"
		"commit_operation":
			return {"pass": "本轮不调整", "draw_card": "支付费用并三选一", "move_card": "移动已装卡", "set_arrows": "确认主攻方向"}.get(str(action.get("operation", "")), "提交配置")
		"public_decision": return "希望启用公开效果" if bool(action.get("activate", false)) else "不启用公开效果"
		"public_bid": return "公开竞价 %d" % int(action.get("amount_min", 0))
		"pass_public_bid": return "放弃本次竞价"
		"next_hand": return "开始下一手"
		"leave_table": return "带筹码离桌"
		_: return str(action.get("type", "操作"))


func _phase_display_name(phase: String) -> String:
	return {"TEAM_SELECTION": "组建暗队", "BETTING": "下注", "OPERATION_COMMIT": "配置选择", "DRAFT_SELECTION": "装备/效果三选一", "PUBLIC_COMMIT": "公开效果表决", "PUBLIC_BID": "公开效果竞价", "BATTLE_READY": "准备战斗", "BATTLE_REPLAY": "战斗回放", "SETTLED": "本手结算"}.get(phase, phase)


func _winner_display(winner: String) -> String:
	return {"player": "玩家胜利", "opponent": "对手胜利", "tie": "平局"}.get(winner, winner)


func _summarize_public_effects(effects: Array) -> String:
	if effects.is_empty(): return "无"
	var labels: Array[String] = []
	for effect: Variant in effects:
		if effect is Dictionary:
			labels.append(str(effect.get("id", "?")))
		else:
			labels.append(str(effect))
	return " / ".join(labels)


func _on_viewport_resized() -> void:
	if ui_root == null:
		return
	var size := get_viewport().get_visible_rect().size
	var scale_factor := size.y / 1080.0
	ui_root.scale = Vector2.ONE * scale_factor
	ui_root.position = Vector2((size.x - 1920.0 * scale_factor) * 0.5, 0.0)
	if composition != null:
		composition.parallax_enabled = false
		for index in range(player_cards.size()):
			player_cards[index].place_held_from_screen(camera, [0.110, 0.205, 0.300][index], 0.92, 0.33, 4.8)
			player_cards[index].rotation.z = [deg_to_rad(-14.0), 0.0, deg_to_rad(14.0)][index]
		for index in range(opponent_cards.size()):
			opponent_cards[index].place_from_screen(composition, camera, [0.34, 0.50, 0.66][index], 0.365, 0.12)
		for key: String in slot_labels:
			var target: Vector3 = composition.target_points[key]
			var point: Vector2 = camera.unproject_position(composition.anchor_nodes[key].global_position)
			slot_labels[key].position = (point - ui_root.position) / scale_factor + Vector2(-14.0, -10.0)
		for label_name: String in amount_labels:
			var normalized: Vector2 = {"玩家演示额": Vector2(0.83, 0.68), "对手演示额": Vector2(0.28, 0.16), "奖池演示额": Vector2(0.79, 0.43)}[label_name]
			amount_labels[label_name].position = (normalized * size - ui_root.position) / scale_factor
		entry_slider.value = entry_elapsed
		if entry_time_label != null:
			entry_time_label.text = "%.2f / 4.80 秒" % entry_elapsed
		if entry_elapsed >= 4.8:
			_apply_entry_time(4.8)


func _process(delta: float) -> void:
	if entry_playing:
		entry_elapsed = minf(4.8, entry_elapsed + delta)
		_apply_entry_time(entry_elapsed)
		if entry_slider != null:
			entry_slider.set_value_no_signal(entry_elapsed)
		if entry_time_label != null:
			entry_time_label.text = "%.2f / 4.80 秒" % entry_elapsed
		if entry_elapsed >= 4.8:
			entry_playing = false
			entry_play_button.text = "重播4.8秒入场段"
	_hover_ray_pick()
	if game_controller != null and game_session != null:
		_maybe_complete_first_table_tutorial()
		automatic_action_cooldown = maxf(0.0, automatic_action_cooldown - delta)
		if automatic_action_cooldown <= 0.0:
			if game_controller.pending_battle_replay:
				_finish_pending_battle_replay()
				automatic_action_cooldown = 0.25
			elif game_session.state.phase != "TEAM_SELECTION" and _drive_opponent_once():
				automatic_action_cooldown = 0.25
		_refresh_game_loop_ui()


func _apply_entry_time(seconds: float) -> void:
	entry_elapsed = clampf(seconds, 0.0, 4.8)
	entry_ready = entry_elapsed >= 4.8
	if entry_elapsed <= 0.70:
		opponent_entry.set_walk_time(entry_elapsed)
	else:
		opponent_entry.set_sit_progress(_entry_progress(entry_elapsed, 1.35, 0.75))
	var seat_drag := _entry_progress(entry_elapsed, 0.70, 0.65) * (1.0 - _entry_progress(entry_elapsed, 2.10, 0.70))
	entry_chair.visible = entry_elapsed >= 0.70 and entry_elapsed < 2.80
	var chair_pixel := Vector2(get_viewport().size.x * 0.515, get_viewport().size.y * 0.355)
	entry_chair.global_position = camera.project_ray_origin(chair_pixel) + camera.project_ray_normal(chair_pixel) * 17.7 - camera.global_basis.z * (0.15 * seat_drag)
	for side: String in ["player", "opponent"]:
		var dealer: Node3D = dealers.dealer_nodes[side]
		var home: Transform3D = dealer_home_transforms[side]
		var arrive := _entry_progress(entry_elapsed, 0.0, 0.70)
		var away_sign := -1.0 if side == "player" else 1.0
		dealer.global_transform = home
		dealer.global_position = home.origin + camera.global_basis.x * away_sign * 0.30 * (1.0 - arrive)
		var reach := _entry_progress(entry_elapsed, 1.35, 0.75) * (1.0 - _entry_progress(entry_elapsed, 3.70, 0.70))
		var settle := _entry_progress(entry_elapsed, 3.70, 0.70)
		if entry_elapsed >= 4.40:
			reach = 0.16 * (1.0 - _entry_progress(entry_elapsed, 4.40, 0.40))
		dealers.set_entry_reach(side, reach, settle)
	for index in range(player_chip_stacks.size()):
		var player_stack: Node3D = player_chip_stacks[index]
		var p_start: Vector3 = entry_start_positions["PC%d" % index]
		var p_target := _world_at_screen(Vector2(0.845 + index * 0.035, 0.80), 0.05)
		player_stack.visible = entry_elapsed >= 2.10
		player_stack.global_position = _entry_arc(p_start, p_target, _entry_progress(entry_elapsed, 2.10 + index * 0.025, 0.70), 0.12)
		var opponent_stack: Node3D = opponent_chip_stacks[index]
		var o_start: Vector3 = entry_start_positions["OC%d" % index]
		var o_target := _world_at_screen(Vector2(0.29 + index * 0.038, 0.25), 0.04)
		opponent_stack.visible = entry_elapsed >= 2.10
		opponent_stack.global_position = _entry_arc(o_start, o_target, _entry_progress(entry_elapsed, 2.10 + index * 0.025, 0.70), 0.12)
	for index in range(player_cards.size()):
		var card: Node3D = player_cards[index]
		var start: Vector3 = entry_start_positions.get("P%d" % index, player_contact)
		var target: Vector3 = entry_target_positions.get("P%d" % index, card.global_position)
		var deal_progress := _entry_progress(entry_elapsed, 2.80 + index * 0.18, 0.65)
		card.global_position = _entry_arc(start, target, deal_progress, 0.10)
		card.visible = entry_elapsed >= 2.80 + index * 0.18
	for index in range(opponent_cards.size()):
		var card: Node3D = opponent_cards[index]
		var start: Vector3 = entry_start_positions.get("O%d" % index, opponent_contact)
		var target: Vector3 = composition._world_at_screen_point(Vector2([0.34, 0.50, 0.66][index], 0.40), 0.15)
		var opponent_deal := _entry_progress(entry_elapsed, 2.95 + index * 0.18, 0.55)
		card.global_position = _entry_arc(start, target, opponent_deal, 0.08)
		card.visible = entry_elapsed >= 2.95 + index * 0.18
	_update_screen_labels()


func _entry_arc(start: Vector3, target: Vector3, progress: float, arc_height: float) -> Vector3:
	return start.lerp(target, progress) + camera.global_basis.y * sin(progress * PI) * arc_height


func _entry_progress(time: float, start: float, duration: float) -> float:
	var linear := clampf((time - start) / duration, 0.0, 1.0)
	return linear * linear * (3.0 - 2.0 * linear)


func _play_entry_timeline() -> void:
	if entry_playing:
		entry_playing = false
		entry_play_button.text = "播放4.8秒入场段"
		return
	entry_elapsed = 0.0
	_apply_entry_time(0.0)
	entry_playing = true
	entry_play_button.text = "暂停入场段"


func _on_entry_slider_changed(value: float) -> void:
	if entry_playing:
		entry_playing = false
		entry_play_button.text = "播放4.8秒入场段"
	_apply_entry_time(value)


func _play_selected_action() -> void:
	preview_action(action_select.get_selected_id())


func preview_action(action_id: int, time_scale: float = 1.0) -> bool:
	if not ACTION_SECONDS.has(action_id):
		return false
	if action_tween != null and action_tween.is_running():
		action_tween.kill()
	action_busy = true
	active_action = action_id
	action_log.append(action_id)
	entry_playing = false
	var duration: float = float(ACTION_SECONDS[action_id]) / maxf(time_scale, 0.01)
	var tween := create_tween().set_parallel(false)
	action_tween = tween
	match action_id:
		12:
			player_cards[0].visible = true
			player_cards[0].global_position = entry_start_positions["P0"]
			player_cards[0].set_face_up(true)
			player_hands.set_pose("left", "left_pinch")
			tween.tween_property(player_cards[0], "global_position", player_cards[0].base_origin, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		15:
			player_hands.set_pose("left", "left_pinch")
			tween.tween_property(player_cards[0], "global_position", player_contact, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		16, 21:
			player_hands.set_pose("left", "left_release")
			for index in range(player_cards.size()):
				var target: Vector3 = entry_target_positions["P%d" % index]
				tween.tween_property(player_cards[index], "global_position", target, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(float(index) * 0.06)
		17:
			_select_card(0 if selected_card_index < 0 else selected_card_index)
			tween.tween_property(player_cards[selected_card_index], "global_position", player_cards[selected_card_index].base_origin + player_cards[selected_card_index].get_lift_vector() * 0.085, duration)
		18, 26:
			player_hands.set_pose("right", "right_push")
			var chip_start: Vector3 = composition.anchor_nodes["P_CHIPS"].global_position + Vector3.UP * 0.10
			if action_id == 26:
				chip_start = composition.anchor_nodes["O_CHIPS"].global_position + Vector3.UP * 0.10
			flying_chip.global_position = chip_start
			tween.tween_property(flying_chip, "global_position", pot_tray.global_position + Vector3.UP * 0.16, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		19, 29:
			player_hands.set_pose("right", "right_rest")
			tween.tween_property(flying_chip, "global_position", player_chip_stacks[2].global_position + Vector3.UP * 0.14, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		20:
			tween.tween_property(opponent_cards[0].face_pivot, "rotation:x", 0.0, duration * 0.5)
			tween.tween_property(opponent_cards[0].face_pivot, "rotation:x", PI, duration * 0.5)
		22:
			_install_selected_card(duration)
		23:
			_swap_slot_cards(duration)
		24:
			_set_aim_target(2 if active_action == 24 else 1)
			var aim_material := StandardMaterial3D.new()
			aim_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			aim_material.albedo_color = Color("c69b57")
			tween.tween_callback(func() -> void: _draw_aim_line(aim_material))
		25:
			_set_signs_revealed(true)
			tween.tween_interval(duration)
		27:
			for card in opponent_cards:
				tween.tween_property(card.face_pivot, "rotation:x", 0.0, duration * 0.45)
				tween.tween_property(card.face_pivot, "rotation:x", PI, duration * 0.55)
		28:
			status_label.text = "配置锁定演示；未接战斗规则或经济结算"
			tween.tween_interval(duration)
		30, 31:
			_reset_stage_objects(duration)
		32:
			tween.tween_property(title_banner, "position:y", 72.0, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		13, 14:
			for index in range(player_cards.size()):
				var target: Vector3 = player_cards[index].base_origin + Vector3.UP * (0.015 if action_id == 13 else -0.12)
				tween.tween_property(player_cards[index], "global_position", target, duration).set_delay(float(index) * 0.05)
			if action_id == 14:
				player_hands.set_pose("left", "left_release")
	var callback_delay := duration
	tween.tween_callback(func() -> void:
		action_busy = false
		status_label.text = _action_status(action_id)
		for index in range(player_cards.size()):
			player_cards[index].set_hover_state(false, index == selected_card_index)
	).set_delay(callback_delay)
	return true


func _action_status(action_id: int) -> String:
	return "AC%02d 预演结束 · 固定演示筹码不扣账 · 不代表完整人物动画或battle逻辑" % action_id


func _select_card(index: int) -> void:
	selected_card_index = clampi(index, 0, player_cards.size() - 1)
	for card_index in range(player_cards.size()):
		player_cards[card_index].set_hover_state(false, card_index == selected_card_index)
	var data: Dictionary = PLAYER_DEMOS[selected_card_index]
	readout_label.text = "%s  %s   %s   （固定演示候选，不扣费）" % [data.id, data.title, data.body.replace("\n", " · ")]
	readout_label.visible = true
	status_label.text = "已选 %s；请选择桌边任一己方装备/效果扣槽。" % data.title


func _install_selected_card(duration_override: float = -1.0) -> void:
	if selected_card_index < 0:
		_select_card(0)
	var slot_index := slot_select.get_selected_id()
	selected_slot = SLOT_IDS[clampi(slot_index, 0, 5)]
	var card: Node3D = player_cards[selected_card_index]
	var target_screen: Vector3 = composition.target_points[selected_slot]
	var target_position: Vector3 = composition._world_at_screen_point(Vector2(target_screen.x, target_screen.y), target_screen.z + 0.14)
	var duration := duration_override if duration_override > 0.0 else ACTION_SECONDS[22]
	if duration_override > 0.0:
		action_tween.set_parallel(true)
		action_tween.tween_property(card, "global_position", target_position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		action_tween.tween_property(card, "scale", Vector3.ONE * 0.28, duration)
		action_tween.set_parallel(false)
		return
	if duration_override < 0.0:
		if action_tween != null and action_tween.is_running():
			action_tween.kill()
		action_busy = true
		var local_tween := create_tween()
		action_tween = local_tween
		local_tween.set_parallel(true)
		local_tween.tween_property(card, "global_position", target_position, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		local_tween.tween_property(card, "scale", Vector3.ONE * 0.28, duration)
		local_tween.set_parallel(false)
		local_tween.tween_callback(func() -> void:
			action_busy = false
			status_label.text = "%s 已视觉安装到 %s；不修改真实装备状态。" % [PLAYER_DEMOS[selected_card_index].title, selected_slot]
		)
		return
	card.global_position = target_position
	card.scale = Vector3.ONE * 0.28
	status_label.text = "%s 已视觉安装到 %s；不修改真实装备状态。" % [PLAYER_DEMOS[selected_card_index].title, selected_slot]


func _swap_slot_cards(duration: float) -> void:
	var first := player_cards[0]
	var second := player_cards[1]
	var first_target: Vector3 = composition._world_at_screen_point(Vector2(composition.target_points["P1_SLOT_EQ"].x, composition.target_points["P1_SLOT_EQ"].y), 0.20)
	var second_target: Vector3 = composition._world_at_screen_point(Vector2(composition.target_points["P1_SLOT_FX"].x, composition.target_points["P1_SLOT_FX"].y), 0.20)
	var tween := action_tween
	tween.set_parallel(true)
	tween.tween_property(first, "global_position", second_target, duration).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(second, "global_position", first_target, duration).set_trans(Tween.TRANS_CUBIC)
	tween.set_parallel(false)


func _reset_stage_objects(duration: float) -> void:
	var tween := action_tween
	tween.set_parallel(true)
	for index in range(player_cards.size()):
		tween.tween_property(player_cards[index], "global_position", entry_target_positions["P%d" % index], duration)
		tween.tween_property(player_cards[index], "scale", Vector3.ONE, duration)
	for stack in player_chip_stacks:
		tween.tween_property(stack, "global_position", entry_target_positions["player_chips"], duration)
	for stack in opponent_chip_stacks:
		tween.tween_property(stack, "global_position", entry_target_positions["opponent_chips"], duration)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void:
		for index in range(player_cards.size()):
			player_cards[index].set_face_up(true)
			player_cards[index].visible = true
		status_label.text = "舞台物件回到固定演示静态状态；经济记录未触碰。"
	)


func _set_aim_target(lane: int) -> void:
	var from_key: String = ["P1", "P2", "P3"][clampi(lane - 1, 0, 2)]
	var to_key: String = ["O1", "O2", "O3"][clampi(lane - 1, 0, 2)]
	_draw_aim_line(Color("c69b57"), composition.anchor_nodes[from_key].global_position, composition.anchor_nodes[to_key].global_position)


func _draw_aim_line(color: Variant, from_world: Vector3 = Vector3.ZERO, to_world: Vector3 = Vector3.ZERO) -> void:
	if from_world == Vector3.ZERO:
		from_world = composition.anchor_nodes["P1"].global_position
		to_world = composition.anchor_nodes["O3"].global_position
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color if color is Color else Color("c69b57")
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	mesh.surface_add_vertex(from_world + Vector3.UP * 0.08)
	mesh.surface_add_vertex(to_world + Vector3.UP * 0.08)
	mesh.surface_end()
	ray_marker.mesh = mesh
	status_label.text = "3D 主攻指向演示；未提交或改动任何战斗指令。"


func _set_signs_revealed(revealed: bool) -> void:
	if sign_nodes.is_empty():
		for index in range(2):
			var sign := Label3D.new()
			sign.name = "ConsentWoodSign_%d" % index
			sign.text = "同意" if index == 0 else "不同意"
			sign.font = font
			sign.font_size = 56
			sign.pixel_size = 0.003
			sign.modulate = Color("e2d1ad")
			sign.position = _world_at_screen(Vector2(0.40 + index * 0.20, 0.56), 0.22)
			add_child(sign)
			sign_nodes.append(sign)
	for sign in sign_nodes:
		sign.visible = revealed
	status_label.text = "双方同意签视觉示意；未采集玩家意见。" if revealed else status_label.text


func _hover_ray_pick() -> void:
	if not is_inside_tree() or camera == null or not entry_ready:
		return
	var pointer := get_viewport().get_mouse_position()
	var hit := raycast_screen(pointer)
	var hovered_id: String = str(hit.get("card_id", ""))
	for index in range(player_cards.size()):
		player_cards[index].set_hover_state(hovered_id == player_cards[index].card_id, index == selected_card_index)
	if not hovered_id.is_empty():
		_show_content_detail(hovered_id, "world_card")
	elif hovered_detail_owner == "world_card":
		_hide_content_detail("world_card")


func raycast_screen(screen_position: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen_position)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen_position) * 160.0)
	query.collision_mask = 4 | 8 | 16 | 32
	query.collide_with_areas = true
	query.collide_with_bodies = true
	query.hit_back_faces = true
	var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	last_hit = result
	return result


func raycast_normalized(point: Vector2) -> Dictionary:
	var size := get_viewport().get_visible_rect().size
	return raycast_screen(Vector2(point.x * size.x, point.y * size.y))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not entry_ready:
			status_label.text = "入场动作进行中；牌桌输入暂未开放。"
			return
		var hit := raycast_screen(event.position)
		if hit.is_empty():
			status_label.text = "此处无舞台碰撞；射线已沿相机方向执行。"
			return
		var collider: Object = hit.collider
		if collider is Area3D:
			if collider.has_meta("card_id"):
				var hit_card_id: String = collider.get_meta("card_id")
				for index in range(player_cards.size()):
					if player_cards[index].card_id == hit_card_id:
						_select_card(index)
						return
				status_label.text = "命中 3D 卡背 %s；此处为静态对手展示位。" % hit_card_id
				return
			if collider.has_meta("slot_id"):
				var id: String = collider.get_meta("slot_id")
				slot_select.select(SLOT_IDS.find(id))
				selected_slot = id
				status_label.text = "射线命中 3D 扣槽：%s；可安装已选固定演示候选。" % id
				return
			if collider.has_meta("chip_stack"):
				status_label.text = "射线命中真实 3D 筹码堆；演示额不扣账。"
				return
		status_label.text = "射线命中舞台 3D 几何：%s" % collider.name


func _update_screen_labels() -> void:
	if camera == null or not is_inside_tree():
		return
	if ui_root != null:
		for key: String in slot_labels:
			var world_point: Vector3 = slot_meshes[key].global_position
			var pixel := camera.unproject_position(world_point)
			var scale_factor := maxf(get_viewport().get_visible_rect().size.y / 1080.0, 0.001)
			slot_labels[key].position = (pixel - ui_root.position) / scale_factor + Vector2(-9.0, -12.0)
		for label_name: String in amount_labels:
			var screen: Vector2
			match label_name:
				"玩家演示额": screen = camera.unproject_position(entry_target_positions.get("player_chips", Vector3.ZERO)) + Vector2(-45, -66)
				"对手演示额": screen = camera.unproject_position(entry_target_positions.get("opponent_chips", Vector3.ZERO)) + Vector2(-45, -66)
				_: screen = camera.unproject_position(pot_tray.global_position) + Vector2(-55, -62)
			var scale_factor := maxf(get_viewport().get_visible_rect().size.y / 1080.0, 0.001)
			amount_labels[label_name].position = (screen - ui_root.position) / scale_factor


func get_card_by_id(id: String) -> Node3D:
	for card in player_cards:
		if card.card_id == id:
			return card
	for card in opponent_cards:
		if card.card_id == id:
			return card
	return null


func get_action_count() -> int:
	return ACTIONS.size()


func get_slot_count() -> int:
	return slot_meshes.size()
