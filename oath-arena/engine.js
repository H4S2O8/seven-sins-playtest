import {
  UNITS,
  UNIT_BY_ID,
  CARDS,
  RULES,
  PLEDGES,
  EFFECTS,
} from "./content.js";
export const W = 960,
  H = 430,
  POP_CAP = 6,
  MAIN_CAP = 4,
  DURATION = 18;
export function rng(seed = 1) {
  let a = seed >>> 0;
  return () => {
    a += 0x6d2b79f5;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export const shuffle = (arr, r) =>
  [...arr]
    .sort(() => 0)
    .map((x) => [r(), x])
    .sort((a, b) => a[0] - b[0])
    .map((x) => x[1]);
export const clamp = (n, a, b) => Math.max(a, Math.min(b, n));
export function makeUnit(id, uid) {
  const d = UNIT_BY_ID[id];
  return { uid, id, hp: d.hp, buffs: [], slot: null, mode: "move" };
}
export const living = (side) => side.units.filter((u) => u.hp > 0);
export const population = (us) =>
  us.reduce((n, u) => n + UNIT_BY_ID[u.id].pop, 0);
export function newGame(seed = Date.now(), tutorial = false) {
  return {
    version: 1,
    seed,
    tutorial,
    round: 1,
    money: [40, 40],
    priority: 0,
    sides: [
      { units: [], cards: [], pledges: [] },
      { units: [], cards: [], pledges: [] },
    ],
    phase: "auction",
    auctionKind: "units",
    auctionTurn: 0,
    auctionIndex: 0,
    auctionPool: [],
    history: [],
    deployed: [[], []],
    locked: [],
    selectedCards: [null, null],
    selectedPledges: [null, null],
    cardReady: [{}, {}],
    nominations: [null, null],
    rule: null,
    records: [],
    rounds: [],
    winner: null,
    lastMessage: "",
    fatigue: 0,
  };
}
export function auctionResult(bids, priority) {
  if (bids.some((x) => !Number.isFinite(x) || x < 0 || !Number.isInteger(x)))
    throw Error("出价必须是非负整数");
  const tied = bids[0] === bids[1],
    winner = tied ? priority : bids[0] > bids[1] ? 0 : 1;
  return {
    winner,
    cost: bids[winner],
    priority: tied ? 1 - priority : priority,
  };
}
export function ruleContest(nominations, bids, priority) {
  if (nominations[0] === nominations[1])
    return { rule: nominations[0], winner: null, cost: 0, priority };
  const result = auctionResult(bids, priority);
  return { ...result, rule: nominations[result.winner] };
}
export function stats(u) {
  const d = UNIT_BY_ID[u.id];
  const s = {
    ...d,
    tags: [...d.tags],
    armor: d.tags.includes("armor") ? 4 : 0,
    shields: d.tags.includes("shield") ? 1 : 0,
  };
  for (const b of u.buffs || []) {
    if (b.left <= 0) continue;
    const e = EFFECTS[b.key];
    if (e.tag && !s.tags.includes(e.tag)) s.tags.push(e.tag);
    s.atk += d.atk * (e.atk || 0);
    s.armor += e.armor || 0;
    s.range += e.range || 0;
    s.speed += d.speed * (e.speed || 0);
    s.interval *= 1 - (e.rate || 0);
    s.shields += e.shields || 0;
  }
  s.atk = Math.min(s.atk, d.atk * 2);
  s.armor = Math.min(12, s.armor);
  s.interval = Math.max(0.45, s.interval);
  s.shields = Math.min(3, s.shields);
  return s;
}
export function slotPosition(slot, side) {
  const col = slot % 3,
    row = Math.floor(slot / 3);
  return {
    x: side === 0 ? (row === 0 ? 332 : 156) : row === 0 ? 628 : 804,
    y: 100 + col * 116,
  };
}
export function validDeployment(units, cap = POP_CAP) {
  return (
    units.length > 0 &&
    population(units) <= cap &&
    units.every(
      (u) => u.hp > 0 && Number.isInteger(u.slot) && u.slot >= 0 && u.slot < 6,
    ) &&
    new Set(units.map((u) => u.slot)).size === units.length
  );
}
function blankMetrics() {
  return {
    damage: 0,
    hits: 0,
    kills: 0,
    killPop: 0,
    shieldBreak: 0,
    healing: 0,
    push: 0,
    pull: 0,
    multi: 0,
    centerTime: 0,
    guarded: 0,
    markDamage: 0,
    armorBlock: 0,
  };
}
export function createBattle(deployed, { round = 1 } = {}) {
  const heat = Math.max(0, round - 4);
  const entities = deployed.flatMap((list, side) =>
    list.map((u, i) => {
      const s = stats(u),
        p = slotPosition(u.slot, side);
      return {
        ...s,
        atk: s.atk * (1 + heat * 0.15),
        uid: u.uid,
        unitId: u.id,
        side,
        hp: u.hp,
        maxHp: s.hp,
        ...p,
        startX: p.x,
        startY: p.y,
        mode: u.mode,
        slot: u.slot,
        marked: i === 0,
        cd: 0.35 + i * 0.09,
        wardCd: 2,
        still: 0,
        chargeUsed: false,
        slow: 0,
        damaged: false,
        dealt: 0,
        shield: s.shields,
        dead: false,
        face: side === 0 ? 1 : -1,
      };
    }),
  );
  return {
    entities,
    time: 0,
    duration: DURATION,
    heat,
    healingFactor: Math.max(0.2, 1 - heat * 0.1),
    metrics: [blankMetrics(), blankMetrics()],
    events: [],
    eventId: 0,
    ended: false,
    frames: [],
    fired: 0,
  };
}
function event(b, type, data = {}) {
  b.events.push({ id: ++b.eventId, t: b.time, type, ...data });
  if (b.events.length > 180) b.events.shift();
}
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
function damage(b, source, target, amount, secondary = false) {
  if (target.hp <= 0 || source.hp <= 0) return 0;
  const sm = b.metrics[source.side];
  sm.hits++;
  if (target.shield > 0) {
    target.shield--;
    sm.shieldBreak++;
    event(b, "shield", { x: target.x, y: target.y, side: target.side });
    return 0;
  }
  if (!secondary) {
    const g = b.entities
      .filter(
        (e) =>
          e.side === target.side &&
          e.uid !== target.uid &&
          e.hp > 0 &&
          e.tags.includes("guard") &&
          dist(e, target) < 106,
      )
      .sort((a, c) => dist(a, target) - dist(c, target))[0];
    if (g) {
      const diverted = amount * 0.35;
      amount -= diverted;
      b.metrics[g.side].guarded += diverted;
      damage(b, source, g, diverted, true);
    }
  }
  const blocked = Math.min(Math.max(0, amount - 1), target.armor);
  b.metrics[target.side].armorBlock += blocked;
  const n = Math.min(target.hp, Math.max(1, amount - blocked));
  target.hp = Math.max(0, target.hp - n);
  target.damaged = true;
  target.flash = 0.12;
  sm.damage += n;
  source.dealt += n;
  if (source.marked) sm.markDamage += n;
  event(b, "hit", {
    x: target.x,
    y: target.y,
    n: Math.round(n),
    side: source.side,
  });
  if (source.tags.includes("drain") && !secondary)
    heal(b, source, source, n * 0.23);
  if (target.tags.includes("thorns") && !secondary && target.hp > 0)
    damage(b, target, source, 4, true);
  if (target.hp <= 0 && !target.dead) {
    target.dead = true;
    sm.kills++;
    sm.killPop += target.pop;
    event(b, "death", {
      x: target.x,
      y: target.y,
      side: target.side,
      uid: target.uid,
    });
  }
  return n;
}
function heal(b, source, target, amount) {
  const n = Math.min(amount * b.healingFactor, target.maxHp - target.hp);
  if (n <= 0 || target.hp <= 0) return;
  target.hp += n;
  b.metrics[source.side].healing += n;
  if (n > 1)
    event(b, "heal", {
      x: target.x,
      y: target.y,
      n: Math.round(n),
      side: target.side,
    });
}
function displace(b, s, t, amount, pull = false) {
  if (t.hp <= 0) return;
  const d = Math.max(1, dist(s, t)),
    old = { x: t.x, y: t.y },
    sign = pull ? -1 : 1;
  t.x = clamp(t.x + ((t.x - s.x) / d) * amount * sign, 40, W - 40);
  t.y = clamp(t.y + ((t.y - s.y) / d) * amount * sign, 44, H - 42);
  t.still = 0;
  b.metrics[s.side][pull ? "pull" : "push"] += Math.hypot(
    old.x - t.x,
    old.y - t.y,
  );
  event(b, pull ? "pull" : "push", {
    x: s.x,
    y: s.y,
    tx: t.x,
    ty: t.y,
    side: s.side,
  });
}
function attack(b, s, t) {
  const enemies = b.entities.filter((e) => e.side !== s.side && e.hp > 0);
  let targets = [t];
  if (s.tags.includes("pierce")) {
    const dx = t.x - s.x,
      dy = t.y - s.y,
      d = Math.max(1, dist(s, t));
    targets = enemies.filter((e) => {
      const ex = e.x - s.x,
        ey = e.y - s.y,
        along = (ex * dx + ey * dy) / d,
        perp = Math.abs(ex * dy - ey * dx) / d;
      return (
        e.uid === t.uid || (along > 0 && along <= s.range + 95 && perp < 25)
      );
    });
  }
  if (s.tags.includes("splash"))
    for (const e of enemies)
      if (e.uid !== t.uid && dist(e, t) < 79 && !targets.includes(e))
        targets.push(e);
  if (targets.length > 1) b.metrics[s.side].multi++;
  const charges = s.tags.includes("double") ? 2 : 1;
  event(b, s.range >= 150 ? "bolt" : "slash", {
    x: s.x,
    y: s.y,
    tx: t.x,
    ty: t.y,
    side: s.side,
    kind: s.tags.includes("pierce")
      ? "pierce"
      : s.tags.includes("splash")
        ? "splash"
        : s.art,
  });
  s.attackTime = b.time;
  s.face = t.x >= s.x ? 1 : -1;
  for (let k = 0; k < charges; k++)
    for (const e of targets) {
      if (e.hp <= 0) continue;
      let n = s.atk * (e.uid === t.uid ? 1 : 0.62);
      if (s.tags.includes("siege") && s.still >= 1.2) n *= 1.4;
      if (s.tags.includes("execute") && e.hp / e.maxHp < 0.3) n *= 1.55;
      damage(b, s, e, n);
    }
  if (s.tags.includes("push")) displace(b, s, t, 34);
  if (s.tags.includes("pull")) displace(b, s, t, 48, true);
  if (s.tags.includes("slow")) t.slow = 2;
}
export function stepBattle(b, dt = 0.05) {
  if (b.ended) return;
  b.time = Math.min(b.duration, b.time + dt);
  const alive = b.entities.filter((e) => e.hp > 0);
  // Simultaneous-ish initiative alternates every tick; never random targeting or critical hits.
  const order = Math.floor(b.time / dt) % 2 ? alive : [...alive].reverse();
  for (const e of order) {
    if (e.hp <= 0) continue;
    e.flash = Math.max(0, (e.flash || 0) - dt);
    e.slow = Math.max(0, e.slow - dt);
    e.cd -= dt;
    e.wardCd -= dt;
    if (e.x >= 320 && e.x <= 640) b.metrics[e.side].centerTime += dt;
    if (e.tags.includes("regen")) heal(b, e, e, 1.5 * dt);
    if (e.tags.includes("ward") && e.wardCd <= 0) {
      const ally = alive
        .filter(
          (a) =>
            a.hp > 0 && a.side === e.side && a.shield < 1 && dist(e, a) < 165,
        )
        .sort((a, c) => a.hp / a.maxHp - c.hp / c.maxHp)[0];
      if (ally) {
        ally.shield++;
        event(b, "ward", { x: ally.x, y: ally.y, side: e.side });
      }
      e.wardCd = 5;
    }
    const enemies = b.entities.filter((a) => a.hp > 0 && a.side !== e.side);
    if (!enemies.length) continue;
    const candidates = enemies.filter(
      (a) => a.tags.includes("taunt") && dist(e, a) < 155,
    );
    const target = (candidates.length ? candidates : enemies).sort(
      (a, c) => dist(e, a) - dist(e, c) || a.uid.localeCompare(c.uid),
    )[0];
    const d = dist(e, target);
    if (e.tags.includes("heal") && e.cd <= 0) {
      const ally = b.entities
        .filter(
          (a) =>
            a.side === e.side &&
            a.hp > 0 &&
            a.hp < a.maxHp - 4 &&
            dist(e, a) <= e.range,
        )
        .sort((a, c) => a.hp / a.maxHp - c.hp / c.maxHp)[0];
      if (ally) {
        heal(b, e, ally, 15);
        e.cd = e.interval;
        event(b, "beam", {
          x: e.x,
          y: e.y,
          tx: ally.x,
          ty: ally.y,
          side: e.side,
        });
        continue;
      }
    }
    let moving = false;
    if (e.mode === "move" && d > e.range * 0.9) {
      let speed = e.speed * (e.slow > 0 ? 0.5 : 1);
      if (e.tags.includes("charge") && !e.chargeUsed && d < 210) {
        speed *= 3.4;
        e.charging = true;
      }
      const delta = Math.min(speed * dt, Math.max(0, d - e.range * 0.82));
      if (delta > 0) {
        e.x = clamp(e.x + ((target.x - e.x) / d) * delta, 40, W - 40);
        e.y = clamp(e.y + ((target.y - e.y) / d) * delta, 44, H - 42);
        e.face = target.x >= e.x ? 1 : -1;
        moving = true;
        e.still = 0;
      }
    }
    if (!moving) e.still += dt;
    e.moving = moving;
    if (dist(e, target) <= e.range && e.cd <= 0) {
      if (e.charging && !e.chargeUsed) {
        damage(b, e, target, e.atk * 0.7);
        e.chargeUsed = true;
        e.charging = false;
        event(b, "charge", {
          x: e.startX,
          y: e.startY,
          tx: e.x,
          ty: e.y,
          side: e.side,
        });
      }
      if (!e.tags.includes("siege") || e.still >= 1.2) {
        attack(b, e, target);
        e.cd = e.interval;
      }
    }
  }
  // Soft collision: keep bodies legible without changing player-issued stand orders.
  for (let i = 0; i < alive.length; i++)
    for (let j = i + 1; j < alive.length; j++) {
      const a = alive[i],
        c = alive[j];
      if (a.hp <= 0 || c.hp <= 0) continue;
      const d = dist(a, c),
        min = 23 + (a.pop + c.pop) * 2;
      if (d < min && d > 0.01) {
        const amount = (min - d) * 0.24,
          dx = (a.x - c.x) / d,
          dy = (a.y - c.y) / d;
        if (a.mode === "move") {
          a.x += dx * amount;
          a.y += dy * amount;
        }
        if (c.mode === "move") {
          c.x -= dx * amount;
          c.y -= dy * amount;
        }
      }
    }
  if (
    b.time >= b.duration ||
    [0, 1].some((s) => !b.entities.some((e) => e.side === s && e.hp > 0))
  )
    b.ended = true;
}
export function snapshot(b) {
  return [0, 1].map((side) => {
    const all = b.entities.filter((e) => e.side === side),
      live = all.filter((e) => e.hp > 0),
      m = all.find((e) => e.marked);
    return {
      ...b.metrics[side],
      markHp: m ? (100 * m.hp) / m.maxHp : 0,
      centerPop: live
        .filter((e) => e.x >= 320 && e.x <= 640)
        .reduce((n, e) => n + e.pop, 0),
      shield: live.reduce((n, e) => n + e.shield, 0),
      alivePop: live.reduce((n, e) => n + e.pop, 0),
      aliveCount: live.length,
      losses: all.length - live.length,
      health: live.reduce((n, e) => n + e.hp, 0),
      advance: Math.max(
        0,
        ...live.map((e) => (side === 0 ? e.x - 100 : 860 - e.x)),
      ),
      rear: live.filter((e) => (side === 0 ? e.x < 245 : e.x > 715)).length,
      breach: live.filter((e) => (side === 0 ? e.x > 715 : e.x < 245)).length,
      rangeAlive: live.filter((e) => e.range >= 150).length,
      meleeAlive: live.filter((e) => e.range < 150).length,
      untouched: live.filter((e) => !e.damaged).length,
      wounded: live.filter((e) => e.hp < e.maxHp * 0.5).length,
    };
  });
}
export function resolveRule(rule, metrics) {
  // Resolve at display precision, so a visible tie never hides a failure.
  const visible=s=>Math.round(metrics[s][rule.metric]*10)/10;
  return [0, 1].map(
    (s) =>
      rule.direction *
        (visible(s) - visible(1-s)) >=
      -1e-6,
  );
}
export function pledgeMet(p, m) {
  return p.direction * (m[p.metric] - p.threshold) >= -1e-6;
}
export function simulate(deployed, options) {
  const b = createBattle(deployed, options);
  for (let i = 0; i < 1000 && !b.ended; i++) stepBattle(b);
  return { battle: b, metrics: snapshot(b) };
}
export function applyEffect(side, key, targetUid) {
  const e = EFFECTS[key];
  if (!e) throw Error("Unknown effect " + key);
  let target = side.units.find((u) => u.uid === targetUid && u.hp > 0);
  if (!target)
    target = living(side).sort(
      (a, b) => stats(b).pop - stats(a).pop || b.hp - a.hp,
    )[0];
  const targets = e.all ? living(side) : target ? [target] : [];
  for (const u of targets) {
    if (e.heal) u.hp = Math.min(UNIT_BY_ID[u.id].hp, u.hp + e.heal);
    if (e.duration) {
      const old = u.buffs.find((b) => b.key === key);
      if (old) old.left = Math.max(old.left, e.duration);
      else u.buffs.push({ key, left: e.duration });
    }
  }
  return targets.map((u) => u.uid);
}
export function settle(g, b, targets = [null, null]) {
  const metrics = snapshot(b),
    rule = RULES.find((r) => r.id === g.rule),
    outcomes = resolveRule(rule, metrics);
  const result = {
    round: g.round,
    rule: g.rule,
    metrics,
    outcomes,
    cards: [...g.selectedCards],
    pledges: [...g.selectedPledges],
    rewards: [],
    losses: [[], []],
  };
  for (let s = 0; s < 2; s++) {
    for (const u of g.sides[s].units) {
      const e = b.entities.find((e) => e.uid === u.uid);
      if (e) {
        u.hp = e.hp;
        if (u.hp <= 0) result.losses[s].push(u.uid);
      }
      u.buffs = u.buffs
        .map((v) => ({ ...v, left: v.left - 1 }))
        .filter((v) => v.left > 0);
    }
  }
  for (let s = 0; s < 2; s++) {
    const c = CARDS.find((c) => c.id === g.selectedCards[s]);
    if (c) {
      const key = outcomes[s] ? c.success : c.failure;
      const ids = applyEffect(g.sides[s], key, targets[s]);
      result.rewards.push({ side: s, key, ids, source: "card" });
      g.cardReady[s][c.id] = g.round + 2;
    }
    const p = PLEDGES.find((p) => p.id === g.selectedPledges[s]);
    if (p) {
      const met = pledgeMet(p, metrics[s]);
      if (met) {
        const ids = applyEffect(g.sides[s], p.reward, targets[s]);
        result.rewards.push({ side: s, key: p.reward, ids, source: "pledge" });
      }
      result["pledge" + s] = met;
      g.sides[s].pledges = g.sides[s].pledges.filter((id) => id !== p.id);
    }
  }
  const counts = g.sides.map((s) => living(s).length);
  g.winner =
    counts[0] === 0 && counts[1] === 0
      ? "draw"
      : counts[0] === 0
        ? 1
        : counts[1] === 0
          ? 0
          : null;
  g.rounds.push(result);
  g.phase = "result";
  return result;
}
export function availableRules(deployed, r) {
  const all = deployed.flat().map(stats);
  const has = (tags) => all.some((u) => tags.some((t) => u.tags.includes(t)));
  const meaningful = RULES.filter((rule) => {
    const k = rule.metric;
    if (["shield", "shieldBreak"].includes(k)) return has(["shield", "ward"]);
    if (k === "healing") return has(["heal", "regen", "drain"]);
    if (k === "push") return has(["push"]);
    if (k === "pull") return has(["pull"]);
    if (k === "guarded") return has(["guard"]);
    if (k === "multi") return has(["splash", "pierce"]);
    if (k === "armorBlock") return all.some((u) => u.armor > 0);
    if (k === "rangeAlive") return all.some((u) => u.range >= 150);
    if (k === "meleeAlive") return all.some((u) => u.range < 150);
    return true;
  });
  return shuffle(meaningful, r).slice(0, 10);
}
export function autoDeploy(
  side,
  cap = MAIN_CAP,
  existing = [],
  style = "balanced",
) {
  const used = new Set(existing.map((u) => u.uid)),
    slots = new Set(existing.map((u) => u.slot));
  let out = existing.map((u) => ({ ...u })),
    pop = population(out);
  const options = living(side)
    .filter((u) => !used.has(u.uid))
    .sort((a, b) => {
      const score = (u) => {
        const s = stats(u);
        return (
          s.atk / s.interval +
          s.hp * 0.1 +
          (style === "defense" ? s.armor * 5 : s.speed * 0.12)
        );
      };
      return score(b) - score(a) || a.uid.localeCompare(b.uid);
    });
  for (const u of options) {
    const s = stats(u);
    if (pop + s.pop > cap) continue;
    const prefer = s.range >= 150 ? [4, 3, 5, 1, 0, 2] : [1, 0, 2, 4, 3, 5];
    const slot = prefer.find((i) => !slots.has(i));
    if (slot === undefined) continue;
    out.push({ ...u, slot, mode: s.range >= 175 ? "stand" : "move" });
    slots.add(slot);
    pop += s.pop;
  }
  if (!out.some((u) => u.mode === "move" && !stats(u).tags.includes("heal"))) {
    const vanguard =
      out.find((u) => !used.has(u.uid) && !stats(u).tags.includes("heal")) ||
      out.find((u) => !used.has(u.uid));
    if (vanguard) vanguard.mode = "move";
  }
  return out;
}
export function botPlan(self, enemyMain, ownMain, round, ready, r) {
  const cards = self.cards.filter((id) => (ready[id] || 0) <= round);
  const forecasts = simulate([enemyMain, ownMain], { round }).metrics;
  const card =
    CARDS.find((c) => c.id === cards[Math.floor(r() * cards.length)]) || null;
  return {
    card: card?.id || null,
    metrics: forecasts,
    desired: card
      ? EFFECTS[card.failure].heal && !EFFECTS[card.success].heal
        ? false
        : r() > 0.35
      : true,
  };
}
