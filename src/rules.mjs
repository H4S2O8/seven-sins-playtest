export const SIN_IDS = [
  "gluttony",
  "wrath",
  "greed",
  "pride",
  "envy",
  "lust",
  "sloth",
];
export const clamp = (n, lo = 0, hi = 100) => Math.max(lo, Math.min(hi, n));
export const meters = () => Object.fromEntries(SIN_IDS.map((id) => [id, 0]));
export function createPlayer() {
  return { hp: 100, maxHp: 100, pain: 0, sins: meters(), alive: true };
}
export function createHuman(id) {
  return { id, hp: 100, sins: meters(), unmet: meters(), state: "dormant" };
}
export function inject(player, human, sin, amount = 20) {
  if (
    !SIN_IDS.includes(sin) ||
    !Number.isFinite(amount) ||
    amount <= 0 ||
    !player.alive ||
    ["rescued", "recovered"].includes(human.state)
  )
    return 0;
  const transferred = Math.min(amount, player.sins[sin], 100 - human.sins[sin]);
  player.sins[sin] -= transferred;
  human.sins[sin] += transferred;
  if (transferred > 0) human.state = "desiring";
  return transferred;
}
export function rescueDuration(sinValue) {
  return sinValue < 40 ? Infinity : 18 - (clamp(sinValue, 40, 100) - 40) * 0.2;
}
export function satisfyPlayer(player, sin, relief = 8) {
  if (!SIN_IDS.includes(sin)) return;
  player.pain = clamp(player.pain - relief);
}
export function frustratePlayer(player, sin, severity = 6) {
  if (!SIN_IDS.includes(sin) || player.sins[sin] < 60) return;
  player.pain = clamp(player.pain + severity * (0.5 + player.sins[sin] / 100));
  if (player.pain >= 100) player.alive = false;
}
export function satisfyHuman(human, sin) {
  if (SIN_IDS.includes(sin)) human.unmet[sin] = 0;
}
export function advanceHuman(human, dt, satisfied = new Set()) {
  if (
    human.state !== "desiring" ||
    human.hp <= 0 ||
    !Number.isFinite(dt) ||
    dt <= 0
  )
    return false;
  for (const sin of SIN_IDS) {
    if (satisfied.has(sin) || human.sins[sin] < 40) human.unmet[sin] = 0;
    else human.unmet[sin] += dt;
    if (human.unmet[sin] >= rescueDuration(human.sins[sin])) {
      human.state = "rescued";
      return true;
    }
  }
  return false;
}
export function killReward(player, sin, source = "basic") {
  if (SIN_IDS.includes(sin))
    player.sins[sin] = clamp(player.sins[sin] + (source === "basic" ? 4 : 0.5));
}
export function spend(player, sin, cost) {
  if (
    !SIN_IDS.includes(sin) ||
    !Number.isFinite(cost) ||
    cost < 0 ||
    player.sins[sin] < cost
  )
    return false;
  player.sins[sin] -= cost;
  return true;
}
export function basicStage(value) {
  return [20, 40, 60, 75, 90].filter((threshold) => value >= threshold).length;
}
export function rescueReturn(player, human, ledger, bonusRate = 0) {
  if (human.state !== "rescued" || ledger.has(human.id)) return false;
  ledger.add(human.id);
  for (const sin of SIN_IDS)
    player.sins[sin] = clamp(
      player.sins[sin] +
        human.sins[sin] +
        Math.min(8, human.sins[sin] * clamp(bonusRate, 0, 0.2)),
    );
  return true;
}
