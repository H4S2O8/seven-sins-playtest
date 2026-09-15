import { CODES, passiveRank } from "./progression.mjs";
const scaled = (rank, start, step) => (rank ? start + (rank - 1) * step : 0);
export function passiveStats(save, sin, context = {}) {
  const c = CODES[sin],
    r = (i) => passiveRank(save, c + String(i).padStart(2, "0"));
  const out = {
    damageReduction: 0,
    frustrationReduction: 0,
    reliefBonus: 0,
    injectRange: 1,
    injectDuration: 1,
    rescueBonus: 0.05 * r(20),
    protection: 0,
    protectionTime: 0,
    dashRecovery: 1,
    staggerReduction: 0,
  };
  if (["wrath", "greed", "pride", "envy", "lust", "sloth"].includes(sin))
    out.frustrationReduction = scaled(r(13), 0.08, 0.06);
  if (["gluttony", "greed", "envy", "lust", "sloth"].includes(sin))
    out.reliefBonus = scaled(r(15), 0.1, 0.08);
  if (["wrath", "greed", "pride", "sloth"].includes(sin))
    out.injectRange = 1 + 0.15 * r(16);
  else if (["gluttony", "lust"].includes(sin))
    out.injectDuration = 1 - 0.1 * r(16);
  if (["wrath", "gluttony", "pride", "envy", "sloth"].includes(sin)) {
    out.protection = scaled(r(18), 0.15, 0.05);
    out.protectionTime = r(18) ? 1 + r(18) : 0;
  }
  if (sin === "wrath" && context.chasing)
    out.damageReduction += scaled(r(11), 0.06, 0.04);
  if (sin === "gluttony" && context.lowHP)
    out.damageReduction += scaled(r(12), 0.08, 0.05);
  if (sin === "greed" && context.orbit >= 3 && context.sideHit)
    out.damageReduction += scaled(r(11), 0.06, 0.04);
  if (sin === "pride" && context.surrounded && context.frontHit)
    out.damageReduction += scaled(r(12), 0.08, 0.05);
  if (sin === "envy" && context.copied)
    out.damageReduction += scaled(r(11), 0.08, 0.05);
  if (sin === "lust" && context.linkNear)
    out.damageReduction += scaled(r(11), 0.08, 0.05);
  if (sin === "sloth" && context.stationary && context.frontHit)
    out.damageReduction += scaled(r(11), 0.08, 0.05);
  if (sin === "lust" && context.linkNear)
    out.dashRecovery -= scaled(r(12), 0.1, 0.07);
  if (sin === "sloth" && context.stationary) out.staggerReduction = scaled(r(12), 0.15, 0.1);
  if (sin === "pride" && context.stationary)
    out.staggerReduction = scaled(r(14), 0.15, 0.1);
  if (sin === "greed" && context.orbit >= 4)
    out.staggerReduction = scaled(r(14), 0.15, 0.1);
  if (sin === "wrath" && context.chasing)
    out.staggerReduction = scaled(r(14), 0.15, 0.1);
  return out;
}
