import { distance, segmentDistance } from "./geometry.mjs";
import { CODES, passiveRank } from "./progression.mjs";
const IDS = Object.fromEntries(Object.entries(CODES).map(([id, c]) => [c, id]));
const choose = (r, a, b, c) => [a, b, c][r - 1];
export class Abilities {
  constructor(design, context) {
    this.design = design;
    this.c = context;
    this.cooldowns = {};
    this.fields = [];
    this.pending = [];
  }
  reset() {
    this.cooldowns = {};
    this.fields = [];
    this.pending = [];
  }
  active(sin) {
    const c = this.c;
    return (c.save.equipped[CODES[sin]] || [])
      .map((code) =>
        this.design.trees
          .find((t) => t.id === code[0])
          .nodes.find((n) => n.code === code),
      )
      .filter((n) => n.type === "主动");
  }
  modifier(code) {
    return passiveRank(this.c.save, code);
  }
  buff(entity, name, seconds, value = 1) {
    entity.buffs ??= {};
    if(name==='shield'&&entity.buffs[name]){value=Math.max(value,entity.buffs[name].value);seconds=Math.max(seconds,entity.buffs[name].left);}
    entity.buffs[name] = { left: seconds, value };
  }
  value(entity, name) {
    return entity.buffs?.[name]?.value || 0;
  }
  proc(entity, key, seconds) {
    entity.procs ??= {};
    if (entity.procs[key] > 0) return false;
    entity.procs[key] = seconds;
    return true;
  }
  after(delay, fn) {
    this.pending.push({ delay, fn });
  }
  field(x, y, radius, seconds, dps, sin, extra = {}) {
    this.fields.push({
      x,
      y,
      radius,
      left: seconds,
      total: seconds,
      dps,
      sin,
      ...extra,
    });
  }
  tick(dt) {
    this.c.player.recovery = Math.max(0, (this.c.player.recovery || 0) - dt);
    for (const code in this.cooldowns)
      this.cooldowns[code] = Math.max(0, this.cooldowns[code] - dt);
    for (const e of [this.c.player, ...this.c.guards(), ...this.c.humans()]) {
      for (const k in e.procs) e.procs[k] = Math.max(0, e.procs[k] - dt);
      for (const [k, b] of Object.entries(e.buffs || {})) {
        b.left -= dt;
        if (b.left <= 0) delete e.buffs[k];
      }
    }
    for (const p of this.pending) p.delay -= dt;
    const due = this.pending.filter((p) => p.delay <= 0);
    this.pending = this.pending.filter((p) => p.delay > 0);
    due.forEach((p) => p.fn());
    for (const f of this.fields) {
      f.left -= dt;
      for (const e of this.c.guards()) {
        if (distance(f, e) > f.radius) continue;
        if (f.dps) this.c.hit(e, f.dps * dt, "skill", f.sin);
        if (f.slow) this.buff(e, "slow", 0.1, f.slow);
      }
      if (f.dps)
        for (const h of this.c.humans())
          if (distance(f, h) < f.radius)
            this.c.harmHuman?.(h, f.dps * dt * 0.5);
    }
    this.fields = this.fields.filter((f) => f.left > 0);
  }
  enemyAction(enemy) {
    for (const f of this.fields)
      if (f.actionDamage && distance(f, enemy) < f.radius)
        this.c.hit(enemy, f.actionDamage, "skill", f.sin);
  }
  cast(sin, slot) {
    const c = this.c,
      p = c.player,
      n = this.active(sin)[slot];
    if (!n) return "该位置没有装备主动技能";
    if (p.recovery > 0) return "动作尚未收回";
    const rank = c.save.learned[n.code],
      code = n.code,
      i = n.i;
    if (this.cooldowns[code] > 0)
      return `冷却剩余 ${this.cooldowns[code].toFixed(1)} 秒`;
    const target = c.target(),
      human = c.human(),
      mouse = c.mouse,
      base = 25 * (1 + p.sins[sin] / 100),
      damage = (mult, e = target) => {
        if (e) c.hit(e, base * mult, "skill", sin);
      },
      aoe = (center, r, mult) => {
        c.guards()
          .filter((e) => distance(center, e) < r)
          .forEach((e) => damage(mult, e));
        for (const h of c.humans())
          if (distance(center, h) < r) c.harmHuman?.(h, base * mult * 0.5);
      };
    const targetRequired = [
      "W01",
      "W02",
      "W03",
      "W04",
      "W05",
      "W06",
      "W08",
      "W10",
      "W19",
      "G01",
      "G05",
      "P01",
      "P02",
      "P03",
      "P08",
      "P19",
      "E01",
      "E03",
      "E04",
      "E05",
      "E19",
    ];
    if (targetRequired.includes(code) && (!target || distance(p, target) > 540))
      return "需要范围内的机器人目标";
    if (code[0] === "L" && ![17, 19].includes(i) && !c.link)
      return "先用普攻建立连接";
    if (code[0] === "E" && [2, 6, 8, 10].includes(i) && !p.copied)
      return "先用普攻夺取一种模块";
    if (
      code === "E08" &&
      (distance(p, mouse) > 240 + 60 * this.modifier("E09") ||
        c.canPlace?.(mouse) === false)
    )
      return "模仿体必须放在可见范围内的地面上";
    if (i === 17 && (!human || distance(p, human) > 240))
      return "需要靠近并指向一个尚未断联的人";
    const cost = i === 17 ? 24 : Number.parseFloat(n.cast),
      ammo =
        sin === "greed"
          ? { 1: 2, 2: 1, 3: 2, 4: 3, 5: 4, 6: 3, 8: 1, 10: c.orbit.length }[
              i
            ] || 0
          : 0,
      residue = sin === "gluttony" ? { 2: 1, 4: 1, 6: 1, 10: 3 }[i] || 0 : 0;
    if (p.sins[sin] < cost) return `需要 ${cost} 点欲望`;
    if (c.orbit.length < ammo || (code === "A10" && ammo < 4))
      return "捕获弹不足；先用贪婪普攻抓取";
    if ((p.residue || 0) < residue) return "残渣不足；吞食击败机器人可获得";
    if (i === 17 && human.sins[sin] > 80)
      return "目标容纳不足20点，请直接右键注入";
    p.sins[sin] -= cost;
    c.orbit.splice(0, ammo);
    p.residue = (p.residue || 0) - residue;
    this.cooldowns[code] = Number.parseFloat(n.cd);
    p.recovery = 0.25;
    if(sin==='envy'&&[1,5,6,8,10].includes(i)&&this.value(p,'nextCopyRecovery')){p.recovery*=1-this.value(p,'nextCopyRecovery');delete p.buffs.nextCopyRecovery;}
    if (code === "E06" && this.modifier("E07"))
      p.recovery *= 1 - choose(this.modifier("E07"), 0.15, 0.25, 0.35);
    if (residue && this.modifier("G14") && this.proc(p,'G14',8))
      this.buff(
        p,
        "staggerResist",
        2 + this.modifier("G14"),
        choose(this.modifier("G14"), 0.15, 0.25, 0.35),
      );
    c.effect(p.x, p.y, c.color(sin), 65);
    const shield = (fraction, seconds) =>
        this.buff(p, "shield", seconds, p.maxHp * fraction),
      push = (e, amount, direction = p) => {
        if (e.heavy && !this.value(e, "weakstance")) return 0;
        const resistance = this.value(e, "anchor");
        return c.move(
          e,
          {
            x: e.x + (e.x - direction.x) * 5,
            y: e.y + (e.y - direction.y) * 5,
          },
          amount * (1 - resistance),
        );
      };
    if (i === 17) {
      human.sins[sin] += 20;
      human.state = "desiring";
      human.chosen = sin;
      if (sin === "wrath") human.markId = target?.id;
      if (sin === "gluttony" || sin === "greed") human.preferred = c.prop()?.id;
      if (sin === "lust")
        human.partnerId = c.humans().find((h) => h !== human)?.id;
      if (sin === "sloth") human.restSpot = { ...mouse };
      if (sin === "pride" || sin === "envy") human.targetId = target?.id;
      this.buff(
        human,
        "protected",
        3,
        0.15 + 0.05 * this.modifier(code[0] + "18"),
      );
      return null;
    }
    switch (code) {
      case "W01":
        c.mark = target;
        this.buff(
          target,
          "slow",
          choose(rank, 1, 1.3, 1.6),
          choose(rank, 0.1, 0.15, 0.2),
        );
        break;
      case "W02":
        c.move(p, target, choose(rank, 180, 210, 240));
        damage(choose(rank, 1.2, 1.5, 1.8));
        break;
      case "W03":
        damage(choose(rank, 1, 1.25, 1.5));
        this.buff(
          target,
          "vulnerable",
          rank === 3 ? 4 : 3,
          choose(rank, 0.1, 0.15, 0.2),
        );
        break;
      case "W04":
        c.move(
          p,
          {
            x: target.x + (target.x - p.x) * 0.3,
            y: target.y + (target.y - p.y) * 0.3,
          },
          choose(rank, 240, 300, 360),
        );
        this.buff(
          p,
          "protected",
          choose(rank, 0.5, 0.7, 0.9),
          choose(rank, 0.1, 0.15, 0.2),
        );
        break;
      case "W05":
        damage(choose(rank, 1.8, 2.2, 2.6));
        target.stun = choose(rank, 0.4, 0.6, 0.8);
        break;
      case "W06": {
        const start = { x: p.x, y: p.y };
        c.move(p, target, choose(rank, 300, 360, 420));
        damage(choose(rank, 1.6, 1.9, 2.2));
        const m = this.modifier("W07");
        if (m)
          for (const e of c.guards())
            if (e !== target && segmentDistance(e, start, p) < 35)
              damage(choose(m, 0.4, 0.6, 0.8), e);
        c.mark = target;
        break;
      }
      case "W08": {
        const start = { x: p.x, y: p.y };
        c.move(p, target, 240);
        const mult = () =>
          choose(rank, 1, 1.25, 1.5) *
          (this.modifier("W09") && p.x < target.x !== !!target.flip
            ? 1 + choose(this.modifier("W09"), 0.2, 0.35, 0.5)
            : 1);
        damage(mult());
        this.after(0.5, () => {
          c.move(p, start, 240);
          damage(mult());
        });
        break;
      }
      case "W10":
        for (let j = 0; j < 3; j++)
          this.after(j * 0.25, () => {
            const e = c.target();
            if (e) {
              c.move(p, e, 250);
              damage(choose(rank, 1.2, 1.45, 1.7), e);
            }
          });
        break;
      case "W19":
        push(target, choose(rank, 120, 150, 180));
        break;
      case "G01":
        damage(choose(rank, 1.4, 1.75, 2.1));
        target.stun = choose(rank, 0.5, 0.7, 0.9);
        break;
      case "G02":
        shield(choose(rank, 0.1, 0.15, 0.2), choose(rank, 4, 5, 6));
        break;
      case "G03":
        this.field(
          mouse.x,
          mouse.y,
          100,
          choose(rank, 2, 2.5, 3),
          (base * choose(rank, 1, 1.35, 1.7)) / choose(rank, 2, 2.5, 3),
          sin,
        );
        break;
      case "G04":
        p.hp = Math.min(
          p.maxHp,
          p.hp + p.maxHp * choose(rank, 0.08, 0.12, 0.16),
        );
        break;
      case "G05":
        damage(choose(rank, 1.8, 2.2, 2.6) * (target.heavy ? 1.4 : 1));
        break;
      case "G06":
        c.projectiles(
          mouse,
          rank + 4,
          (base * choose(rank, 1.4, 1.75, 2.1)) / (rank + 4),
          sin,
          0.6,
          0,
          {
            acid: this.modifier("G07")
              ? base * choose(this.modifier("G07"), 0.3, 0.45, 0.6)
              : 0,
          },
        );
        break;
      case "G08":
        for (const e of c.guards())
          if (distance(p, e) < 240) {
            if (!e.heavy) c.move(e, p, choose(rank, 90, 120, 150));
            damage(
              choose(rank, 1, 1.3, 1.6) +
                (e.heavy && this.modifier("G09")
                  ? choose(this.modifier("G09"), 0.4, 0.7, 1)
                  : 0),
              e,
            );
          }
        break;
      case "G10":
        this.field(
          p.x,
          p.y,
          230,
          choose(rank, 2, 2.5, 3),
          (base * choose(rank, 3, 3.75, 4.5)) / choose(rank, 2, 2.5, 3),
          sin,
        );
        break;
      case "G19": {
        const food = c.prop();
        if (food) food.active = false;
        break;
      }
      case "A01":
        this.field(
          p.x,
          p.y,
          65,
          choose(rank, 2, 2.5, 3),
          base * choose(rank, 1.6, 2, 2.4),
          sin,
        );
        break;
      case "A02":
        shield(choose(rank, 0.1, 0.15, 0.2), choose(rank, 2, 3, 4));
        break;
      case "A03": {
        const point = { ...mouse };
        this.field(point.x, point.y, 60, 1, 0, sin);
        this.after(1, () => {
          aoe(point, choose(rank, 60, 72, 84), choose(rank, 3.6, 4.5, 5.4));
          c.effect(point.x, point.y, c.color(sin), 100);
        });
        break;
      }
      case "A04":
        this.field(
          mouse.x,
          mouse.y,
          130,
          choose(rank, 2, 2.5, 3),
          base * choose(rank, 1, 1.2, 1.4),
          sin,
        );
        break;
      case "A05":
        aoe(p, choose(rank, 120, 138, 156), choose(rank, 4, 4.8, 5.6));
        break;
      case "A06":
        c.projectiles(
          mouse,
          3,
          base * choose(rank, 1.8, 2.2, 2.6),
          sin,
          0.35,
          this.modifier("A07"),
        );
        break;
      case "A08":
        c.projectiles(mouse, 1, base * choose(rank, 3.5, 4.25, 5), sin, 0, 1, {
          vulnerable: this.modifier("A09")
            ? choose(this.modifier("A09"), 0.1, 0.15, 0.2)
            : 0,
        });
        break;
      case "A10":
        c.projectiles(mouse, ammo, base * choose(rank, 2, 2.5, 3), sin, 0.7);
        break;
      case "A19":
        this.after(choose(rank, 0.7, 0.55, 0.4), () => {
          const prop = c.prop();
          if (prop?.active) {
            prop.active = false;
            c.orbit.push({ phase: 0 });
            c.satisfy("greed");
          }
        });
        break;
      case "P01":
        damage(choose(rank, 1, 1.3, 1.6));
        c.prideResult(push(target, choose(rank, 100, 120, 140)));
        break;
      case "P02":
        target.stun = choose(rank, 0.6, 0.8, 1);
        target.flip = !target.flip;
        break;
      case "P03":
        this.buff(
          target,
          "weakstance",
          choose(rank, 2, 3, 4),
          choose(rank, 0.1, 0.18, 0.26),
        );
        break;
      case "P04":
        this.buff(
          p,
          "protected",
          choose(rank, 1.5, 2, 2.5),
          choose(rank, 0.25, 0.3, 0.35),
        );
        break;
      case "P05":
        this.buff(
          p,
          "anchor",
          choose(rank, 2, 3, 4),
          choose(rank, 0.4, 0.5, 0.6),
        );
        break;
      case "P06": {
        const angle = Math.atan2(mouse.y - p.y, mouse.x - p.x),
          half = ((90 + 15 * this.modifier("P07")) * Math.PI) / 360;
        for (const e of c.guards())
          if (
            distance(p, e) < 200 &&
            Math.abs(
              Math.atan2(
                Math.sin(Math.atan2(e.y - p.y, e.x - p.x) - angle),
                Math.cos(Math.atan2(e.y - p.y, e.x - p.x) - angle),
              ),
            ) <= half
          ) {
            damage(choose(rank, 1.5, 1.8, 2.1), e);
            c.prideResult(push(e, choose(rank, 120, 140, 160)));
          }
        break;
      }
      case "P08":
        damage(choose(rank, 1, 1.3, 1.6));
        c.prideResult(
          push(target, 150, {
            x: target.x - (mouse.x - target.x),
            y: target.y - (mouse.y - target.y),
          }),
        );
        if (this.modifier("P09"))
          target.stun =
            0.5 * (1 + choose(this.modifier("P09"), 0.15, 0.2, 0.25));
        break;
      case "P10":
        for (const e of c.guards())
          if (distance(p, e) < choose(rank, 180, 210, 240)) {
            damage(choose(rank, 1.8, 2.2, 2.6), e);
            c.prideResult(push(e, 180));
          }
        break;
      case "P19":
        this.buff(
          target,
          "anchor",
          choose(rank, 2, 3, 4),
          choose(rank, 0.2, 0.3, 0.4),
        );
        break;
      case "E01":
        p.copied = true;
        target.stun = choose(rank, 2, 3, 4);
        c.satisfy("envy");
        if (this.modifier("E12") && this.proc(p, "E12", 8))
          shield(
            choose(this.modifier("E12"), 0.04, 0.07, 0.1),
            this.modifier("E12") === 3 ? 4 : 3,
          );
        break;
      case "E02":
        shield(choose(rank, 0.15, 0.22, 0.3), choose(rank, 2, 2.5, 3));
        break;
      case "E03":
        target.cd = Math.max(target.cd, choose(rank, 0.6, 0.9, 1.2));
        break;
      case "E04":
        this.buff(
          target,
          "weakened",
          choose(rank, 3, 4, 5),
          choose(rank, 0.15, 0.22, 0.3),
        );
        break;
      case "E05":
        target.stun = 0.6;
        p.copied = true;
        if (this.modifier("E12") && this.proc(p, "E12", 8))
          shield(
            choose(this.modifier("E12"), 0.04, 0.07, 0.1),
            this.modifier("E12") === 3 ? 4 : 3,
          );
        c.projectiles(mouse, 1, base * choose(rank, 1, 1.3, 1.6), sin, 0);
        break;
      case "E06":
        c.projectiles(mouse, 1, base * choose(rank, 1.5, 1.85, 2.2), sin, 0);
        break;
      case "E08": {
        const point = { ...mouse };
        this.after(0.3, () => {
          c.effect(point.x, point.y, c.color(sin), 60);
          aoe(point, 100, choose(rank, 1.3, 1.7, 2.1));
        });
        break;
      }
      case "E10":
        for (let j = 0; j < 2; j++)
          this.after(j * 0.25, () =>
            c.projectiles(mouse, 1, base * choose(rank, 1.2, 1.5, 1.8), sin, 0),
          );
        break;
      case "E19":
        target.stun = choose(rank, 1.5, 2, 2.5);
        this.buff(target, "sealed", target.stun);
        break;
      case "L01": {
        const l = c.link;
        const x = l.x - p.x,
          y = l.y - p.y,
          d = Math.hypot(x, y) || 1;
        c.move(
          p,
          { x: p.x - (y / d) * 300, y: p.y + (x / d) * 300 },
          choose(rank, 120, 150, 180),
        );
        break;
      }
      case "L02":
        c.move(p, c.link, choose(rank, 180, 240, 300));
        break;
      case "L03":
        this.buff(
          p,
          "speed",
          choose(rank, 2, 2.5, 3),
          choose(rank, 0.2, 0.28, 0.36),
        );
        break;
      case "L04":
        c.link.stun = choose(rank, 0.6, 0.9, 1.2);
        break;
      case "L05": {
        const l = c.link,
          a =
            Math.atan2(p.y - l.y, p.x - l.x) +
            choose(rank, Math.PI / 2, (Math.PI * 2) / 3, (Math.PI * 5) / 6),
          d = distance(p, l);
        c.move(p, { x: l.x + Math.cos(a) * d, y: l.y + Math.sin(a) * d }, 360);
        break;
      }
      case "L06": {
        const line = (fraction = 1) => {
          if (c.link)
            for (const e of c.guards())
              if (segmentDistance(e, p, c.link) < 35)
                damage(choose(rank, 1.8, 2.25, 2.7) * fraction, e);
        };
        line();
        if (this.modifier("L07"))
          this.after(0.3, () =>
            line(choose(this.modifier("L07"), 0.25, 0.35, 0.45)),
          );
        break;
      }
      case "L08":
        this.buff(
          p,
          "lineSlow",
          choose(rank, 2, 3, 4),
          choose(rank, 0.15, 0.22, 0.3),
        );
        break;
      case "L10":
        this.buff(
          p,
          "lineDamage",
          choose(rank, 1.5, 1.8, 2.1),
          (base * choose(rank, 3.6, 4.5, 5.4)) / choose(rank, 1.5, 1.8, 2.1),
        );
        break;
      case "L19":
        if (human) push(human, choose(rank, 60, 90, 120));
        else if (target) {
          push(target, choose(rank, 60, 90, 120));
          damage(0.2);
        }
        break;
      case "S01":
        c.cover(
          mouse,
          choose(rank, 2, 3, 4),
          p.maxHp * choose(rank, 0.15, 0.22, 0.3),
        );
        break;
      case "S02":
        for (const e of c.guards())
          if (distance(p, e) < choose(rank, 90, 108, 126)) {
            damage(choose(rank, 0.3, 0.4, 0.5), e);
            push(e, 80);
          }
        break;
      case "S03":
        if (target) target.stun = choose(rank, 1, 1.4, 1.8);
        break;
      case "S04":
        c.move(p, mouse, choose(rank, 120, 150, 180));
        break;
      case "S05":
        shield(choose(rank, 0.12, 0.18, 0.24), choose(rank, 2, 3, 4));
        break;
      case "S06":
        this.buff(
          p,
          "fieldPower",
          choose(rank, 3, 4, 5),
          choose(rank, 1.2, 1.3, 1.4),
        );
        break;
      case "S08": {
        const point = { x: p.x, y: p.y };
        this.field(p.x, p.y, 180, choose(rank, 1, 1.5, 2), 0, sin, {
          actionDamage: base * choose(rank, 0.5, 0.6, 0.7),
        });
        if (this.modifier("S09"))
          this.after(choose(rank, 1, 1.5, 2), () =>
            aoe(point, 180, choose(this.modifier("S09"), 0.8, 1.1, 1.4)),
          );
        break;
      }
      case "S10":
        this.field(p.x, p.y, 220, choose(rank, 4, 5, 6), 0, sin, {
          actionDamage: base * choose(rank, 2, 2.4, 2.8),
        });
        break;
      case "S19": {
        const point = { ...mouse };
        this.after(choose(rank, 0.7, 0.55, 0.4), () => {
          for (const h of c.humans())
            if (distance(h, point) < choose(rank, 60, 78, 96)) {
              h.restTime = 0;
              h.unmet.sloth = Math.max(0, h.unmet.sloth);
              this.buff(h, "disturbed", 2);
            }
          c.effect(point.x, point.y, c.color(sin), 100);
        });
        break;
      }
      default:
        throw new Error("Missing active implementation " + code);
    }
    return null;
  }
}
