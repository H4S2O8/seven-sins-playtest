extends Resource
class_name TableLayout

@export var camera_position := Vector3(0.0, 6.0, 9.0)
@export var camera_target := Vector3(0.0, 0.0, 0.0)
@export_range(20.0, 80.0, 0.1) var camera_fov := 46.0
@export var table_height := 0.02
@export var anchor_targets: Dictionary = {
	"TABLE_FAR_L": Vector3(0.18, 0.25, 0.02),
	"TABLE_FAR_R": Vector3(0.82, 0.25, 0.02),
	"TABLE_NEAR_L": Vector3(-0.06, 0.93, 0.02),
	"TABLE_NEAR_R": Vector3(1.06, 0.93, 0.02),
	"OPP_HEAD": Vector3(0.50, 0.095, 1.00),
	"OPP_TORSO": Vector3(0.50, 0.18, 0.65),
	"O_RECEIVE": Vector3(0.73, 0.23, 0.48),
	"DEALER_P": Vector3(0.085, 0.21, 2.35),
	"DEALER_O": Vector3(0.925, 0.17, 2.35),
	"P_RECEIVE": Vector3(0.16, 0.72, 0.38),
	"P_HAND": Vector3(0.205, 0.825, 0.10),
	"P_CHIPS": Vector3(0.88, 0.84, 0.12),
	"O_CHIPS": Vector3(0.285, 0.215, 0.12),
	"POT": Vector3(0.79, 0.47, 0.08),
	"RULE_CARD": Vector3(0.085, 0.40, 0.12),
	"ARENA_CARD": Vector3(0.085, 0.55, 0.12),
	"PUBLIC_1": Vector3(0.90, 0.34, 0.12),
	"PUBLIC_2": Vector3(0.90, 0.44, 0.12),
	"PUBLIC_3": Vector3(0.90, 0.54, 0.12),
	"P1": Vector3(0.32, 0.64, 0.08),
	"P2": Vector3(0.50, 0.64, 0.08),
	"P3": Vector3(0.68, 0.64, 0.08),
	"O1": Vector3(0.34, 0.36, 0.08),
	"O2": Vector3(0.50, 0.36, 0.08),
	"O3": Vector3(0.66, 0.36, 0.08),
	"P1_SLOT_EQ": Vector3(0.289, 0.695, 0.08),
	"P1_SLOT_FX": Vector3(0.351, 0.695, 0.08),
	"P2_SLOT_EQ": Vector3(0.469, 0.695, 0.08),
	"P2_SLOT_FX": Vector3(0.531, 0.695, 0.08),
	"P3_SLOT_EQ": Vector3(0.649, 0.695, 0.08),
	"P3_SLOT_FX": Vector3(0.711, 0.695, 0.08),
	"O1_SLOT_EQ": Vector3(0.315, 0.393, 0.08),
	"O1_SLOT_FX": Vector3(0.365, 0.393, 0.08),
	"O2_SLOT_EQ": Vector3(0.475, 0.393, 0.08),
	"O2_SLOT_FX": Vector3(0.525, 0.393, 0.08),
	"O3_SLOT_EQ": Vector3(0.635, 0.393, 0.08),
	"O3_SLOT_FX": Vector3(0.685, 0.393, 0.08),
	"ACTION_TRAY": Vector3(0.55, 0.90, 0.08),
	"NOTICE": Vector3(0.50, 0.965, 0.08),
	"O_SPEECH": Vector3(0.68, 0.105, 1.35),
}

@export var tolerance_px := 2.0
