export const SHIFT_SECONDS = 30;
export function startShift(save) {
  if (save.shift?.remaining > 0) return "这一班尚未结束";
  const workers = save.residents.filter(
    (r) => r.mode === "work" && r.strain < 80,
  );
  if (!workers.length) return "先安排至少一位能够工作的居民";
  save.shift = { remaining: SHIFT_SECONDS, workers: workers.map((r) => r.id) };
  return null;
}
// Only active game time advances production. Reloading or changing the clock creates no resources.
export function tickFarm(save, dt) {
  if (!save.shift || save.shift.remaining <= 0) return false;
  save.shift.remaining = Math.max(0, save.shift.remaining - dt);
  if (save.shift.remaining > 0) return false;
  const working = new Set(save.shift.workers);
  for (const r of save.residents) {
    if (working.has(r.id) && r.mode === "work" && r.strain < 80) {
      save.currency += 12 + (save.upgrades?.capacity || 0) * 2;
      r.strain = Math.min(100, r.strain + 25);
      if (r.strain >= 80) r.mode = "rest";
    } else r.strain = Math.max(0, r.strain - 25);
  }
  return true;
}
export function recoverResidents(save) {
  for (const r of save.residents)
    if (r.mode === "rest") r.strain = Math.max(0, r.strain - 10);
}
