export class BossDirector {
  constructor() {
    this.clock = 0;
    this.next = 2;
    this.pattern = 0;
    this.telegraphs = [];
    this.addTimer = 8;
    this.phase = 0;
  }
  tick(dt, boss, player) {
    this.clock += dt;
    const events = [];
    const phase = Math.min(2, Math.floor((1 - boss.hp / boss.maxHp) * 3));
    if (phase !== this.phase) {
      this.phase = phase;
      events.push({ type: "phase", phase });
    }
    this.next -= dt;
    this.addTimer -= dt;
    if (this.addTimer <= 0) {
      this.addTimer = 18;
      events.push({ type: "adds", count: 4 });
    }
    if (this.next <= 0) {
      const kind = this.pattern++ % 3;
      this.next = 5.5 - this.phase * 0.5;
      boss.pose = 1;
      const aim = Math.atan2(player.y - boss.y, player.x - boss.x);
      this.telegraphs.push({
        kind,
        left: 1.25 + dt,
        aim,
        x: player.x,
        y: player.y,
      });
    }
    for (const t of this.telegraphs) {
      t.left -= dt;
      if (t.left > 0) continue;
      boss.pose = 2;
      boss.open = 2.5;
      if (t.kind === 0)
        for (let i = -2 - this.phase; i <= 2 + this.phase; i++)
          events.push({
            type: "bullet",
            x: boss.x,
            y: boss.y,
            angle: t.aim + i * 0.14,
            speed: 220,
          });
      if (t.kind === 1) {
        const count = 16 + this.phase * 4;
        for (let i = 0; i < count; i++) {
          const angle = (i * Math.PI * 2) / count + this.clock * 0.2;
          const delta = Math.atan2(
            Math.sin(angle - t.aim),
            Math.cos(angle - t.aim),
          );
          if (Math.abs(delta) < 0.38) continue;
          events.push({
            type: "bullet",
            x: boss.x,
            y: boss.y,
            angle,
            speed: 160,
          });
        }
      }
      if (t.kind === 2)
        events.push({
          type: "pulse",
          x: t.x,
          y: t.y,
          radius: 75 + this.phase * 15,
        });
    }
    this.telegraphs = this.telegraphs.filter((t) => t.left > 0);
    boss.open = Math.max(0, (boss.open || 0) - dt);
    if (!boss.open && !this.telegraphs.length) boss.pose = 0;
    return events;
  }
}
