const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const root = process.cwd();
const sourceRelative = "sin-squad-design/04-场地与公共效果.md";
const sourcePath = path.join(root, sourceRelative);
const outputDir = path.join(root, "sin-squad-godot/content/environment");
const implementedIds = new Set(["AR01", "AR02", "AR03", "AR04", "AR05", "AR06", "AR07", "AR08", "AR09", "AR10", "AR11", "AR13", "AR14", "AR15", "AR16", "AR17", "AR19", "AR20", "PE05", "PE09", "PE10", "PE12", "PE17", "PE18", "PE21", "PE22", "PE23", "PE26", "PE30", "PE31", "PE32", "PE35", "PE36", "PE38", "PE39", "PE46", "PE47", "PE48", "PE50"]);

// Explicit per-ID event contracts. This table is authored from each rule, never inferred from card prose.
const requirements = {
  AR01: ["prepare_attack", "melee_cross_prep_override"],
  AR02: ["prepare_attack", "melee_cross_prep_override"],
  AR03: ["before_hit", "attack_damage_type_target_multiplier"],
  AR04: ["battle_start,before_hit", "per_unit_ranged_attack_cover"],
  AR05: ["prepare_attack", "armor_kind_and_first_natural_attack_counters"],
  AR06: ["hit", "cross_melee_attack_completion_status"],
  AR07: ["hp_lost", "same_event_actual_loss_fanout_no_chain"],
  AR08: ["periodic", "independent_tick_root_and_global_tick_event"],
  AR09: ["hit", "natural_melee_attack_completion_counter,self_loss"],
  AR10: ["prepare_attack", "flight_armor_kind_timed_prep_multiplier"],
  AR11: ["before_hit,hit", "per_unit_first_attack_reduction_and_removal"],
  AR12: ["hit", "extra_attack_identity_actual_loss_capture"],
  AR13: ["periodic", "base_armor_vs_temporary_armor_modifier"],
  AR14: ["battle_start", "base_T_ticks_deterministic_argmax_and_barrier"],
  AR15: ["hp_lost", "exact_health_ratio_threshold_and_one_shot_shield"],
  AR16: ["pre_battle", "talent_pause_window_without_replay"],
  AR17: ["prepare_attack", "slot_sensitive_melee_cross_prep_delta"],
  AR18: ["before_hit", "per_packet_post_shield_actual_hp_loss_cap"],
  AR19: ["final_departure", "first_team_final_departure_and_timed_shield"],
  AR20: ["prepare_attack", "per_target_first_attacker_and_one_shot_shield"],
  PE01: ["before_hit", "damage_type_multiplier_before_defense"],
  PE02: ["periodic", "burn_tick_amount_override"],
  PE03: ["before_hit", "first_lightning_hit_current_shield_fractional_consume"],
  PE04: ["status_applied,expiry", "status_expiry_suppression_by_status_id"],
  PE05: ["periodic", "global_interval_event_and_shield_presence_snapshot"],
  PE06: ["status_removed,expiry", "chill_cycle_identity_and_once_per_cycle_damage"],
  PE07: ["before_hit", "fire_hit_chill_consume_before_damage_and_bonus"],
  PE08: ["hit", "attack_segment_append_damage_packet"],
  PE09: ["prepare_attack", "ranged_cross_prep_delta"],
  PE10: ["prepare_attack", "melee_cross_and_light_armor_prep_deltas"],
  PE11: ["shield_broken", "enemy_damage_broke_all_shields_then_next_attack_bonus"],
  PE12: ["pre_battle", "base_armor_modifier_and_elemental_exclusion"],
  PE13: ["hp_lost", "single_attack_segment_actual_loss_threshold_and_armor_break"],
  PE14: ["before_hit", "post_armor_pre_transfer_physical_loss_cap"],
  PE15: ["before_hit", "exact_health_ratio_threshold_and_fractional_armor_ignore"],
  PE16: ["hit", "barrier_absorbed_positive_packet_then_self_loss"],
  PE17: ["periodic", "per_team_exact_health_minimum_tie_by_slot"],
  PE18: ["shield_gained", "numeric_shield_first_gain_and_nonrecursive_grant"],
  PE19: ["hit", "barrier_full_absorb_delayed_damage_same_target"],
  PE20: ["hp_lost,before_hit", "heavy_armor_next_physical_damage_reduction_token"],
  PE21: ["prepare_attack", "per_unit_first_natural_prep_multiplier_only"],
  PE22: ["prepare_attack", "per_unit_first_natural_prep_delay_only"],
  PE23: ["prepare_attack", "natural_attack_count_next_prep_multiplier"],
  PE24: ["hp_lost,prepare_attack", "per_attack_actual_loss_threshold_next_prep_delay"],
  PE25: ["periodic", "global_exact_tick_and_extra_natural_attack_schedule"],
  PE26: ["hit", "distinct_enemy_attacker_window_and_one_shot_shield"],
  PE27: ["before_hit", "reciprocal_public_targeting_attack_multiplier"],
  PE28: ["before_hit,prepare_attack", "prehit_health_threshold_next_attack_prep_multiplier"],
  PE29: ["final_departure,prepare_attack", "team_first_departure_next_natural_prep_adjustment"],
  PE30: ["periodic,prepare_attack,healed", "timed_attack_prep_and_actual_healing_multiplier"],
  PE31: ["pre_battle", "healing_reduction_modifier_before_application"],
  PE32: ["healed", "actual_overheal_to_shield_without_recursive_heal"],
  PE33: ["hp_lost", "per_unit_actual_loss_accumulator_and_post_batch_heal"],
  PE34: ["hit,prepare_attack", "natural_attack_count_self_loss_next_attack_bonus"],
  PE35: ["final_departure", "enemy_final_departure_credit_and_alive_snapshot_heal"],
  PE36: ["before_hit", "exact_health_ratio_strict_below_threshold_attack_multiplier"],
  PE37: ["healed", "actual_heal_accumulator_per_second_targeted_fixed_damage"],
  PE38: ["final_departure,periodic", "first_solo_transition_one_shield_and_four_heal_ticks"],
  PE39: ["periodic", "global_exact_tick_shield_fraction_consume_to_heal_no_overflow_shield"],
  PE40: ["before_hit", "dot_per_packet_flat_reduction_floor_zero"],
  PE41: ["before_hit", "slot_two_attack_dealt_and_received_multiplier"],
  PE42: ["before_hit", "first_attack_from_enemy_slot_two_side_slot_reduction"],
  PE43: ["hp_lost", "melee_cross_attack_actual_loss_next_ally_same_target_bonus"],
  PE44: ["before_hit", "attached_lightning_damage_one_time_pre_redirect_lane_change"],
  PE45: ["prepare_attack", "reciprocal_slot_one_three_melee_prep_override"],
  PE46: ["shield_broken", "first_side_shield_break_alive_opposite_side_shield"],
  PE47: ["periodic", "global_exact_tick_per_team_base_armor_argmax_lightning_damage"],
  PE48: ["periodic", "global_exact_tick_full_hp_one_shot_barrier"],
  PE49: ["final_departure", "deadline_gate_current_attack_target_fixed_damage_no_chain"],
  PE50: ["battle_start,hit", "per_unit_first_attack_mark_reciprocal_heal_or_fixed_damage"]
};

function parseSource(markdown) {
  const heading = /^###\s+(AR\d{2}|PE\d{2})｜([^\r\n]+)\s*$/gm;
  const matches = [...markdown.matchAll(heading)];
  const entries = [];
  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index];
    const start = match.index;
    const sectionEnd = markdown.indexOf("\n## ", start);
    const end = index + 1 < matches.length ? matches[index + 1].index : (sectionEnd >= 0 ? sectionEnd : markdown.length);
    const sourceText = markdown.slice(start, end).trim();
    const ruleMatch = sourceText.match(/(?:^|\n)(机制|效果)：([^\r\n]+)/);
    const compatibilityMatch = sourceText.match(/(?:^|\n)相性：([^\r\n]+)/);
    const presentationMatch = sourceText.match(/演出：([^\r\n]+)/);
    if (!ruleMatch || !compatibilityMatch || !presentationMatch) {
      throw new Error(`${match[1]} source field parse failed`);
    }
    entries.push({
      id: match[1],
      name: match[2],
      category: match[1].slice(0, 2),
      source: "04-场地与公共效果.md",
      source_text: sourceText,
      source_fields: {
        rule_label: ruleMatch[1],
        rule_text: ruleMatch[2],
        compatibility_text: compatibilityMatch[1],
        presentation_text: presentationMatch[1]
      }
    });
  }
  return entries;
}

const markdown = fs.readFileSync(sourcePath, "utf8").replace(/\r\n/g, "\n");
const entries = parseSource(markdown);
const expected = [...Array.from({ length: 20 }, (_, i) => `AR${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 50 }, (_, i) => `PE${String(i + 1).padStart(2, "0")}`)];
if (entries.length !== 70 || entries.some((entry, i) => entry.id !== expected[i])) {
  throw new Error(`Expected ordered AR01..AR20 and PE01..PE50; got ${entries.map((entry) => entry.id).join(",")}`);
}
if (Object.keys(requirements).length !== entries.length) throw new Error("handler requirements must cover all 70 content IDs");

const sourceHash = crypto.createHash("sha256").update(fs.readFileSync(sourcePath)).digest("hex").toUpperCase();
const data = {
  schema_version: 1,
  source: { file: sourceRelative, sha256: sourceHash },
  counts: { AR: 20, PE: 50 },
  entries
};
const handlerManifest = {
  schema_version: 1,
  source: data.source,
  formal_pool_blocked: implementedIds.size !== 70,
  note: "逐项处理器需求表；只有实现并通过真实BattleEngine正例、反例及到期/退场测试后，才可从blocked改为implemented。",
  bindings: entries.map((entry) => {
    const [events, capabilities] = requirements[entry.id];
    return {
      content_id: entry.id,
      logic_handler: `environment_${entry.id}`,
      required_binding_kind: entry.category === "AR" ? "arena" : "public",
      required_owner_key: "",
      required_source_key: `global:${entry.id}`,
      subscribes: events.split(","),
      required_engine_capabilities: capabilities.split(","),
      implementation_status: implementedIds.has(entry.id) ? "implemented" : "not_implemented"
    };
  })
};

fs.mkdirSync(outputDir, { recursive: true });
const dataPath = path.join(outputDir, "environment.json");
const manifestPath = path.join(outputDir, "handler-requirements.json");
if (process.argv.includes("--check")) {
  for (const [filePath, expectedValue] of [[dataPath, data], [manifestPath, handlerManifest]]) {
    if (!fs.existsSync(filePath)) throw new Error(`missing imported artifact: ${filePath}`);
    const actual = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (JSON.stringify(actual) !== JSON.stringify(expectedValue)) throw new Error(`stale or edited import: ${filePath}; rerun importer`);
  }
  process.stdout.write(`PASS: ${entries.length} exact source definitions and ${Object.keys(requirements).length} explicit handler rows match the source; formal pool blocked.\n`);
} else {
  fs.writeFileSync(dataPath, `${JSON.stringify(data, null, 2)}\n`, "utf8");
  fs.writeFileSync(manifestPath, `${JSON.stringify(handlerManifest, null, 2)}\n`, "utf8");
  process.stdout.write(`Imported ${entries.length} source-faithful environment definitions; ${Object.keys(requirements).length} explicit handler requirement rows; formal pool blocked.\n`);
}
