import { basicStage } from "./rules.mjs";
import { CODES } from "./progression.mjs";
export function basicStats(design, save, sin, value) {
  const code = CODES[sin],
    stage = basicStage(value),
    rank = save.basicRanks[code][stage],
    b = design.basics[code];
  return {
    stage,
    damage: b.damage[stage] * (1 + 0.1 * rank),
    range: b.range[stage] * 60 * (1 + 0.025 * rank),
    interval: Math.max(
      0.15,
      b.interval[stage] - (sin === "gluttony" ? 0.1 : 0.02) * rank,
    ),
    shape: b.shapes[stage],
  };
}
