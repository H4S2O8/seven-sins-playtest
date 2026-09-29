"""Focused rule probes, NOT the full game or a win-rate simulation.

Probe A: invulnerable dummy, no death/skills/other chapters, 60 logical ticks.
Probe B: a specified subset of immediate fire + break-shield reward rules.
Probe C: progress floor stops A/S recursion without a trigger-count cap.
"""

from collections import Counter
from itertools import combinations
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]


def schedule(kinds, rewards, horizon=60):
    intervals = [6 if kind == "R" else 6 + 2 * index
                 for index, kind in enumerate(kinds)]
    attack = [2 if kind == "R" else 3 for kind in kinds]
    due = intervals.copy()
    pending_bonus = [0, 0, 0]
    counts = Counter()
    timeline = []
    damage = shield = healing = 0
    attacks = [0, 0, 0]
    for tick in range(1, horizon + 1):
        acting = [i for i in range(3) if due[i] == tick]
        if not acting:
            continue
        dealt = sum(attack[i] + pending_bonus[i] for i in acting)
        damage += dealt
        for i in acting:
            attacks[i] += 1
            pending_bonus[i] = 0
            due[i] = tick + intervals[i]
        current = Counter()
        if rewards:
            for a, b in combinations(acting, 2):
                pair = kinds[a] + kinds[b]
                if pair == "MM":
                    pending_bonus[a] += 1
                    pending_bonus[b] += 1
                    current["C26"] += 1
                elif pair == "RR":
                    healing += 2
                    current["C28"] += 1
                else:
                    shield += 2
                    current["C27"] += 1
            if len(acting) == 3:
                for i in acting:
                    due[i] = max(tick + 1, due[i] - 1)
                current["C29"] += 1
        counts.update(current)
        timeline.append({"tick": tick, "actors": acting, "damage": dealt,
                         "awards": dict(current)})
    return {"formation": kinds, "rewards": rewards, "ticks": horizon,
            "attacks": attacks, "raw_damage": damage,
            "potential_shield": shield, "potential_healing": healing,
            "award_counts": dict(counts), "timeline": timeline}


def fire_loop(include_c04, shield_reward=True):
    """Front F08, allied F06, E04. External shield triggers C04 eligibility.

    Both sides start with 12 HP. A has one shield, B has two.
    A's 2-damage basic breaks B shield. F08 returns immediate 2 burn.
    Positive effective burn damage consumes shields/HP, so C04 then
    grants its origin team's front one shield. F06 heals its own front
    when enemy burn causes HP loss. All other chapter rewards disabled.
    This is a local state probe; full-match opening reachability and the
    effect of other mandatory chapters are explicitly not claimed.
    """
    hp = [12, 12]
    shields = [1, 2]
    next_attack_bonus = [0, 0]
    pending = [("D", 1, 2, 0, False)]
    seen = {}
    trace = []
    for wave in range(100):
        key = (tuple(hp), tuple(shields), tuple(next_attack_bonus), tuple(sorted(pending)))
        if key in seen:
            return {"C04_enabled": include_c04, "reward_is_shield": shield_reward,
                    "same_tick_cycle": True,
                    "first_seen_wave": seen[key], "repeat_wave": wave,
                    "cycle_length": wave - seen[key], "trace": trace}
        seen[key] = wave
        next_events = []
        trace.append({"wave": wave, "hp_before": hp.copy(),
                      "shield_before": shields.copy(), "events": pending})
        for kind, target, value, origin, burn in pending:
            if kind == "S" and hp[target] > 0:
                shields[target] += value
            elif kind == "H" and hp[target] > 0:
                hp[target] = min(12, hp[target] + value)
        for kind, target, value, origin, burn in pending:
            if kind != "D" or hp[target] <= 0:
                continue
            old_shield = shields[target]
            absorbed = min(old_shield, value)
            shields[target] -= absorbed
            loss = min(hp[target], value - absorbed)
            hp[target] -= loss
            if old_shield > 0 and shields[target] == 0 and hp[target] > 0:
                next_events.append(("D", origin, 2, target, True))
            if burn and loss > 0 and hp[origin] > 0:
                next_events.append(("H", origin, 1, origin, False))
            if burn and include_c04 and absorbed + loss > 0 and hp[origin] > 0:
                if shield_reward:
                    next_events.append(("S", origin, 1, origin, False))
                else:
                    next_attack_bonus[origin] += 1
        if not next_events:
            return {"C04_enabled": include_c04, "reward_is_shield": shield_reward,
                    "same_tick_cycle": False, "next_attack_bonus": next_attack_bonus,
                    "settled_after_waves": wave + 1, "hp": hp,
                    "shields": shields, "trace": trace}
        pending = next_events
    raise AssertionError("Probe inconclusive: no repeated state or settlement")


def progress_shield_chain(field_reduces_shield):
    # Initial external A successfully moves due 10 -> 9 at time 0.
    # P03 gives S1. E12 reduces S1 to 0, so the actual rule stops.
    due, shield, advances = 9, 0, 1
    while True:
        actual_shield = max(0, 1 - int(field_reduces_shield))
        shield += actual_shield
        if actual_shield == 0:
            break
        new_due = max(1, due - 1)
        if new_due == due:
            break
        due = new_due
        advances += 1
    return {"E12_minus_one_shield": field_reduces_shield,
            "final_due": due, "shield": shield, "effective_advances": advances,
            "terminates_without_count_cap": True}


baseline = {kind: schedule(kind, False) for kind in ["RRR", "MRR", "MMR", "MMM"]}
enhanced = {kind: schedule(kind, True) for kind in baseline}
assert baseline["RRR"]["raw_damage"] == 60
assert enhanced["RRR"]["raw_damage"] == 66
assert enhanced["RRR"]["potential_healing"] == 66
assert enhanced["MRR"]["potential_shield"] == 44
assert enhanced["MRR"]["potential_healing"] == 22
loop_off, loop_on = fire_loop(False), fire_loop(True)
loop_proposed = fire_loop(True, shield_reward=False)
assert not loop_off["same_tick_cycle"]
assert loop_on["same_tick_cycle"]
assert not loop_proposed["same_tick_cycle"]
floor_checks = [progress_shield_chain(True), progress_shield_chain(False)]
assert floor_checks[0]["effective_advances"] == 1
assert floor_checks[1]["final_due"] == 1

rules = ROOT / "docs/blood-fire-v2-design.md"
report = {
    "scope": "focused deterministic probes; NOT full game; NOT 200 tables; no AI decisions",
    "rules_sha256": hashlib.sha256(rules.read_bytes()).hexdigest(),
    "assumptions": [
        "all three units survive for the dummy schedule; no skills or fields",
        "M attack=3; R attack=2; intervals M=6/8/10 by slot, R=6",
        "potential healing/shield are generated amounts, NOT effective survivability",
        "only C26-C29 enabled in the dummy schedule",
        "fire loop enables F08,F06,E04,C04 only; other mandatory chapters excluded",
        "local loop state uses valid HP/shield values; full opening reachability not proven",
        "progress hypothetical variant removing E12 shield tax is labeled separately",
    ],
    "baseline": baseline, "unlimited_combo_rewards": enhanced,
    "fire_loop_ablation": [loop_off, loop_on, loop_proposed],
    "progress_chain": floor_checks,
    "not_measured": ["win rates", "auction values", "all 204 route reachability",
                     "full-rule interaction", "full-match infinite loop reachability",
                     "human enjoyment"],
}
out = ROOT / "reports/blood-fire-unlimited-probes.json"
out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
for kind in baseline:
    b, e = baseline[kind], enhanced[kind]
    print(kind, "damage", b["raw_damage"], "->", e["raw_damage"],
          "shield", e["potential_shield"], "heal", e["potential_healing"],
          "awards", e["award_counts"])
print("Local fire-loop probe:", loop_on["first_seen_wave"], loop_on["repeat_wave"])
print("Proposed next-attack reward:", loop_proposed["settled_after_waves"],
      "waves; pending damage", loop_proposed["next_attack_bonus"])
print("Progress probes:", floor_checks)
