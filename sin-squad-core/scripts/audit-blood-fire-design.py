"""Static catalogue audit only; this does not simulate combat or prove balance."""

from collections import Counter, defaultdict
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parents[1]
design = (ROOT / "docs/blood-fire-v2-design.md").read_text(encoding="utf-8")
combos = (ROOT / "docs/blood-fire-forgotten-combos.md").read_text(encoding="utf-8")
cards = re.findall(r"^\*\*([BFN]\d{2}) ", design, re.M)
bases = re.findall(r"^\*\*(P\d{2}) ", design, re.M)
fields = re.findall(r"^\|(E\d{2})\|", design, re.M)
chapters = re.findall(r"^\|(C\d{2})\|", combos, re.M)
rows = [line.split("|")[1:4] for line in combos.splitlines()
        if re.match(r"\|\d{3} ", line)]
assert len(cards) == 30 and Counter(x[0] for x in cards) == {"B": 10, "F": 10, "N": 10}
assert len(bases) == 6 and len(fields) == 20 and len(chapters) == 29
assert [int(row[0][:3]) for row in rows] == list(range(1, 205))
assert len(set(row[0][4:] for row in rows)) == 204
known = set(cards + bases + fields)
assert len(known) == 56
coverage = Counter()
same_participants = defaultdict(list)
for title, participants, mechanism in rows:
    refs = re.findall(r"\b[BFNPE]\d{2}\b", participants)
    assert len(refs) >= 2 and set(refs) <= known, title
    assert len([x for x in refs if x[0] in "BFN"]) <= 3, title
    assert sum(x[0] == "P" for x in refs) <= 1, title
    assert sum(x[0] == "E" for x in refs) <= 1, title
    assert len(mechanism) >= 20, title
    coverage.update(refs)
    same_participants["+".join(sorted(refs))].append(title[:3])
assert known <= coverage.keys()

# Each card block contains exactly one skill bullet. Unicode escapes keep this
# utility portable through Windows shells with non-UTF-8 console encodings.
skill_label = "- \u6280\u80fd"
card_blocks = re.split(r"^\*\*[BFN]\d{2} ", design, flags=re.M)[1:]
skill_counts = [block.split("## \u516d\u5f20")[0].count(skill_label)
                for block in card_blocks]
assert skill_counts == [1] * 30, skill_counts
skill_types = Counter()
combat_types = Counter()
interface_sets = {}
for card_id, block in zip(cards, card_blocks):
    line = next(line for line in block.splitlines() if line.startswith(skill_label))
    for kind in ["\u5f00\u542f", "\u53d8\u5f62", "\u6289\u62e9", "\u6307\u5411"]:
        if re.search(kind + r"/", line):
            skill_types[kind] += 1
    header = block.splitlines()[0]
    combat_type = next(kind for kind in ["\u8fd1\u6218", "\u8fdc\u7a0b"] if kind in header)
    combat_types[combat_type] += 1
    interface_line = next(line for line in block.splitlines()
                          if line.startswith("- \u63a5\u53e3\uff1a"))
    outputs = set(re.findall(r"[A-Z]", interface_line))
    assert outputs and outputs <= {"D", "H", "S", "A"}, card_id
    interface_sets[card_id] = sorted(outputs)
assert sum(skill_types.values()) == 30 and len(skill_types) == 4

assert set().union(*(set(v) for v in interface_sets.values())) == {"D", "H", "S", "A"}
base_blocks = re.split(r"^\*\*(P\d{2}) ", design, flags=re.M)[1:]
for offset in range(0, len(base_blocks), 2):
    base_id, block = base_blocks[offset:offset + 2]
    declaration = block.splitlines()[0].split("\u63a5\u53e3", 1)[1]
    assert set(re.findall(r"[A-Z]", declaration)) <= {"D", "H", "S", "A"}, base_id
field_rows = [line.split("|")[1:5] for line in design.splitlines()
              if re.match(r"\|E\d{2}\|", line)]
for field_id, rule, outputs, tradeoff in field_rows:
    declared = set(re.findall(r"[A-Z]", outputs))
    assert declared and declared <= {"D", "H", "S", "A"}, field_id
reward_rows = [line.split("|")[1:5] for line in combos.splitlines()
               if re.match(r"\|C\d{2}\|", line)]
assert all(re.fullmatch(r"[DHSA]:.+", row[3]) for row in reward_rows)

report = {
    "scope": "v2 static-design-audit; no combat execution or balance validation",
    "cards": len(cards), "factions": dict(Counter(x[0] for x in cards)),
    "one_skill_per_card": True, "skill_types": dict(skill_types),
    "combat_types": dict(combat_types),
    "allowed_output_interfaces": ["D", "H", "S", "A"],
    "declared_card_interfaces": interface_sets,
    "base_field_and_reward_interface_declarations_checked": True,
    "baseplates": len(bases), "fields": len(fields),
    "named_routes": len(rows), "shared_achievement_rules": len(chapters),
    "all_catalogue_entries_referenced": True,
    "legal_party_and_global_counts_in_declared_participants": True,
    "same_participant_sets_requiring_distinct_mechanisms":
        {key: value for key, value in same_participants.items() if len(value) > 1},
    "coverage": dict(sorted(coverage.items())),
    "not_verified": ["semantic four-interface closure", "event reachability", "timing consistency by execution",
                     "semantic independence of all routes", "power balance",
                     "auction value", "player enjoyment"],
}
output = ROOT / "docs/blood-fire-forgotten-audit.json"
output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({k: v for k, v in report.items() if k != "coverage"}, ensure_ascii=True, indent=2))
