// A number is a basic attack, and a held number is also the skill modifier.
// Release taps immediately; a short chord window prevents 1+Q also biting.
export class CombatControls {
  constructor(actions) { this.actions = actions; this.held = new Map(); }
  clear() { this.held.clear(); }
  down(key, unlocked) {
    if (/^[1-7]$/.test(key)) {
      const index = Number(key) - 1;
      if (index >= unlocked || this.held.has(key)) return;
      this.held.set(key, {index, age:0, used:false, repeated:false});
      this.actions.select(index); return;
    }
    const slot = ['q','e','r','t','g'].indexOf(key);
    if (slot < 0) return;
    const held = [...this.held.values()].at(-1);
    if (!held) { this.actions.hint('技能需要组合键：按住对应数字，再按 Q / E / R / T / G。'); return; }
    held.used = true;
    this.actions.select(held.index);
    this.actions.skill(slot);
  }
  up(key) {
    const held = this.held.get(key);
    if (!held) return;
    if (!held.used && !held.repeated) { this.actions.select(held.index); this.actions.basic(); }
    this.held.delete(key);
  }
  tick(dt) {
    for (const held of this.held.values()) {
      held.age += dt;
      if (!held.used && held.age >= .22) {
        held.repeated = true; this.actions.select(held.index); this.actions.basic();
      }
    }
  }
}
