import { card, gear, validPlan } from "./content.js";
import type { Battle, Event, Seat, Trace, Unit } from "./types.js";
import { ProcessFields } from "./fields.js";

type Packet = Event & {
  phase: "main" | "tail";
  origin: "skill" | "gear" | "basic" | "field";
  fieldChain?: boolean;
  transferDebit?: boolean;
  transferKey?: string;
  receiptBonus?: number;
  routed?: boolean;
  ticket?: number;
  path?: string[];
};
type Ledger = {
  gain: number;
  loss: number;
  bySource: number[];
  out: Packet[];
  enemyOut: Packet[];
  food: number[];
  gifts: Packet[];
  debts: Packet[];
  blocked: number;
  loan: number[];
};
export interface BattleOptions {
  gearEffects?: boolean;
  skills?: boolean;
  trace?: boolean;
  initiative?: Seat;
}

/** Finite event interpreter. No randomness, hidden-information access or UI dependencies. */
export function battle(
  teams: [Unit[], Unit[]],
  fields: string[] = [],
  options: BattleOptions = {},
): Battle {
  for (const team of teams) {
    if (team.length !== 3) throw Error("Three positions required");
    team.forEach((u, p) => {
      card(u.id);
      if (
        !Number.isInteger(u.raw) ||
        u.raw < 3 ||
        u.raw > 10 ||
        !validPlan(u.id, p, u.plan)
      )
        throw Error("Invalid unit");
      if (u.gear) gear(u.gear);
    });
  }
  const powers = teams.map((t) => t.map((u) => u.raw)) as [number[], number[]];
  const snapshot = powers.map((p) => p.slice());
  const terrain = new ProcessFields(fields);
  const trace: Trace[] = [],
    interactions: string[] = [],
    counts = new Map<string, number>();
  const ledgers: Ledger[][] = teams.map((t) =>
    t.map(() => ({
      gain: 0,
      loss: 0,
      bySource: [0, 0, 0],
      out: [],
      enemyOut: [],
      food: [0, 0],
      gifts: [],
      debts: [],
      blocked: 0,
      loan: [0, 0, 0],
    })),
  );
  const delayed: Packet[] = [],
    primary: Packet[] = [];
  let events = 0,
    serial = 0,
    phase: "main" | "tail" = "main";
  const blockedByTicket = new Map<number, number>(),
    transferred = new Map<string, number>();
  const f = Math.floor,
    other = (s: Seat) => (1 - s) as Seat;
  const order: [Seat, number][] = [];
  for (let p = 0; p < 3; p++)
    for (const s of [0, 1] as Seat[]) order.push([s, p]);
  // Open, alternating hand initiative breaks equal-position priority, never hidden IDs.
  const initiative = options.initiative ?? 0;
  order.sort((a, b) => a[1] - b[1] || (a[0] === initiative ? -1 : 1));
  const active = (s: Seat, p: number, id?: string) =>
    options.skills !== false &&
    teams[s][p].plan.on &&
    (!id || teams[s][p].id === id);
  const gid = (s: Seat, p: number) =>
    options.gearEffects === false ? null : teams[s][p].gear;
  const take = (
    s: Seat,
    p: number,
    key: string,
    amount: number,
    cap: number,
  ) => {
    const k = `${s}:${p}:${key}`,
      n = Math.max(0, Math.min(amount, cap - (counts.get(k) || 0)));
    counts.set(k, (counts.get(k) || 0) + n);
    return n;
  };
  const once = (s: Seat, p: number, key: string) => take(s, p, key, 1, 1) > 0;
  const target = (s: Seat, p: number, i = 0) =>
    teams[s][p].plan.targets[i]?.pos ?? p;
  const mode = (s: Seat, p: number) => teams[s][p].plan.mode;
  const others = (p: number) => [0, 1, 2].filter((q) => q !== p);
  const extreme = (s: Seat, p: number, high = false, current = false) =>
    others(p).sort(
      (a, b) =>
        (high ? -1 : 1) *
          ((current ? powers[s][a] : teams[s][a].raw) -
            (current ? powers[s][b] : teams[s][b].raw)) || a - b,
    )[0];
  const packet = (
    s: Seat,
    p: number,
    ts: Seat,
    t: number,
    n: number,
    kind: Event["kind"],
    label = teams[s][p].id,
    origin: Packet["origin"] = "skill",
  ): Packet => ({
    seat: s,
    source: p,
    targetSeat: ts,
    target: t,
    amount: Math.max(0, f(n)),
    kind,
    depth: 0,
    label,
    phase,
    origin,
  });
  const note = (s: Seat, p: number, what: string) => {
    if (options.trace !== false) interactions.push(`${s}:${p}:${what}`);
  };
  const recordBlocked = (s: Seat, n: number) => {
    if (phase !== "main" || n <= 0) return;
    for (let p = 0; p < 3; p++) {
      if (active(s, p, "GL4"))
        ledgers[s][p].blocked = Math.min(4, ledgers[s][p].blocked + n);
      if (gid(s, p) === "G21") take(s, p, "recycle", n, 2);
    }
  };
  function execute(input: Packet): number {
    if (input.amount <= 0) return 0;
    if (++events > 1024 || input.depth > 48)
      throw Error("Effect cycle bound exceeded");
    const e = {
        ...input,
        path: [...(input.path || [])],
        ticket: input.ticket ?? ++serial,
      },
      { seat: s, source: p, targetSeat: ts, target: t } = e,
      u = teams[ts][t];
    const main = e.phase === "main",
      host = e.kind === "loss" && s !== ts;
    let n = e.amount,
      diverted = 0;
    const fieldQueue: ReturnType<ProcessFields["arrived"]> = [];
    const mods: string[] = [];
    const block = (amount: number, label: string) => {
      const a = Math.min(n, Math.max(0, amount));
      n -= a;
      recordBlocked(ts, a);
      blockedByTicket.set(e.ticket, (blockedByTicket.get(e.ticket) || 0) + a);
      if (a) {
        mods.push(`${label}:${a}`);
        if (host && !e.fieldChain)
          fieldQueue.push(...terrain.blocked(ts, t, a));
      }
      return a;
    };
    const route = (
      amount: number,
      ns: Seat,
      np: number,
      label: string,
      owner = ts,
      position = t,
    ) => {
      const key = `${owner}:${position}:${label}`;
      if (e.path.includes(key)) return 0;
      const a = Math.min(n, Math.max(0, amount));
      n -= a;
      const received =
        e.kind === "gain" && !e.fieldChain ? terrain.transfer(a) : a;
      let actual = 0;
      if (a) {
        e.path.push(key);
        mods.push(`${label}:${a}${received !== a ? "→" + received : ""}`);
        actual = execute({
          ...e,
          targetSeat: ns,
          target: np,
          amount: received,
          depth: e.depth + 1,
          routed: true,
          label: e.label,
        });
        diverted += actual;
      }
      return actual;
    };
    const store = (amount: number, sink: Packet[], label: string) => {
      const a = Math.min(n, Math.max(0, amount));
      n -= a;
      if (a) {
        sink.push({ ...e, amount: a, phase: "tail", routed: true });
        mods.push(`${label}:${a}`);
      }
      return a;
    };
    const bonus = (
      seat: Seat,
      pos: number,
      to: number,
      amount: number,
      label: string,
    ) =>
      execute({
        ...packet(seat, pos, seat, to, amount, "gain", label, "gear"),
        phase: e.phase,
        depth: e.depth + 1,
        fieldChain: e.fieldChain,
      });
    if (!e.routed && e.origin === "skill") {
      const g = gid(s, p);
      if (e.kind === "cost" && g === "G16")
        n -= take(s, p, "discount", Math.min(1, n), 2);
      if (e.kind === "gain") {
        if (g === "G01" && once(s, p, "amp")) {
          n += 2;
          execute({
            ...packet(s, p, s, p, 1, "cost", "G01", "gear"),
            phase: e.phase,
            depth: e.depth + 1,
            fieldChain: e.fieldChain,
          });
          mods.push("G01:+2");
        }
        if (g === "G12") {
          n = once(s, p, "focus") ? n + 3 : Math.max(0, n - 1);
          mods.push("G12");
        }
        if (g === "G23") {
          n = Math.max(0, n + (teams[ts][t].raw < teams[s][p].raw ? 1 : -1));
          mods.push("G23");
        }
        if (main && g === "G17" && take(s, p, "overload", 1, 2)) {
          n += 2;
          execute({
            ...packet(s, p, s, p, 1, "cost", "G17", "gear"),
            depth: e.depth + 1,
            fieldChain: e.fieldChain,
          });
          mods.push("G17:+2");
        }
        const boost = e.fieldChain ? 0 : terrain.boost(s, p);
        if (boost) {
          n += boost;
          mods.push(`F4:+${boost}`);
        }
        if (main && g === "G15") {
          const stored = store(n, delayed, "G15"),
            last = delayed.at(-1);
          if (stored && last && take(s, p, "delaybonus", 1, 2)) last.amount++;
        }
      }
    }
    // Field transformations happen after source output modifiers, before receiver defenses.
    // Each transformation visits a packet only once, including downstream equipment reroutes.
    if (e.kind === "gain" && s === ts && !e.fieldChain && n > 0) {
      if (terrain.has("F7") && !e.path.includes(`${ts}:-1:F7`)) {
        const weakest = powers[ts].indexOf(Math.min(...powers[ts]));
        if (weakest !== t) route(n, ts, weakest, "F7", ts, -1);
      }
      if (terrain.has("F8") && !e.path.includes(`${ts}:-1:F8`) && n > 0) {
        const amount = n;
        n = 0;
        e.path.push(`${ts}:-1:F8`);
        mods.push("F8:强化→敌方削弱");
        execute({
          ...e,
          kind: "loss",
          targetSeat: other(ts),
          amount,
          depth: e.depth + 1,
          routed: true,
        });
      }
    }
    // A packet can visit several receivers, but never the same routing gate twice.
    // Source amplification is still applied once, before any rerouting.
    if (main && n > 0 && e.kind === "gain") {
      if (!e.fieldChain) store(terrain.spill(n), delayed, "F5");
      if (gid(ts, t) === "G09") {
        const a = take(ts, t, "capacitor", n, 4);
        store(a, delayed, "G09");
      }
      if (card(u.id).basic === "reserve") {
        const a = take(ts, t, "reserve", n, 2);
        store(a, delayed, "reserve");
      }
      for (const [os, op] of order) {
        if (!active(os, op) || n === 0) continue;
        const id = teams[os][op].id,
          L = ledgers[os][op],
          a = target(os, op),
          b = target(os, op, 1);
        if (os === ts) {
          if (id === "SL4" && a === t && take(os, op, "sleepPackets", 1, 2)) {
            store(take(os, op, "sleepAmount", n, 5), L.gifts, "SL4");
          }
          if (id === "GL5" && a === t && once(os, op, "sweet")) {
            const z = Math.min(n, 3);
            n -= z;
            L.food[0] += z;
            mods.push("GL5:eaten");
          }
          if (id === "SL3" && op === t && once(os, op, "hermit"))
            route(Math.min(n, 4), ts, a, "SL3", os, op);
          if (
            id === "PR2" &&
            (op === t || a === t) &&
            !e.path.includes(`${os}:${op}:PR2`)
          )
            route(
              take(os, op, "exchange", n, 6),
              ts,
              op === t ? a : op,
              "PR2",
              os,
              op,
            );
          if (id === "PR3" && a === t && take(os, op, "tribute", 1, 2)) {
            route(Math.min(n, 1), os, op, "PR3");
          }
          if (id === "LU2" && a === t && mode(os, op) === 0) {
            L.gain += route(
              take(os, op, "link", f(n / 2), 4),
              ts,
              b,
              "LU2",
              os,
              op,
            );
          }
          if (
            id === "LU5" &&
            (a === t || b === t) &&
            once(os, op, `twin:${t}`)
          ) {
            const z = take(os, op, "twinBank", f(n / 2), 4);
            n -= z;
            L.gain += z;
            mods.push("LU5:bank");
          }
        } else if (
          a === t &&
          (id === "EN1" || id === "EN3" || id === "LU3") &&
          once(os, op, "steal")
        ) {
          const z = Math.min(n, 3);
          n -= z;
          mods.push(id + ":intercept");
          if (id === "EN1")
            execute({
              ...packet(
                os,
                op,
                os,
                op,
                e.fieldChain ? z : terrain.transfer(z),
                "gain",
                id,
              ),
              depth: e.depth + 1,
              fieldChain: e.fieldChain,
            });
          else if (id === "LU3") L.gain += z;
        } else if (id === "LU4" && b === t && once(os, op, "gift"))
          store(Math.min(n, 3), L.gifts, "LU4");
      }
      const g = gid(ts, t);
      if (g === "G02" && once(ts, t, "split"))
        route(f(n / 2), ts, extreme(ts, t), "G02");
      if (g === "G13" && n > 0 && !e.path.includes(`${ts}:${t}:G13`))
        route(take(ts, t, "left", 1, 3), ts, (t + 2) % 3, "G13");
      if (g === "G22" && n > 0)
        route(take(ts, t, "gift", 1, 3), ts, extreme(ts, t, true), "G22");
      if (g === "G24" && n > 0) {
        if (powers[ts][t] > (powers[ts][0] + powers[ts][1] + powers[ts][2]) / 3)
          route(n, ts, extreme(ts, t, false, true), "G24");
        else n += take(ts, t, "equalizer", 1, 2);
      }
      for (let q = 0; q < 3; q++)
        if (
          q !== t &&
          gid(ts, q) === "G03" &&
          n > 0 &&
          !e.path.includes(`${ts}:${q}:G03`)
        )
          route(take(ts, q, "crown", 1, 4), ts, q, "G03", ts, q);
      if (g === "G11" && n > 1 && !e.path.includes(`${ts}:${t}:G11`)) {
        const z = take(ts, t, "prism", f(n / 2), 6),
          qs = others(t),
          key = `${ts}:${t}:G11`;
        n -= z;
        e.path.push(key);
        for (let i = 0; i < 2; i++)
          diverted += execute({
            ...e,
            target: qs[i],
            amount: e.fieldChain
              ? i
                ? f(z / 2)
                : z - f(z / 2)
              : terrain.transfer(i ? f(z / 2) : z - f(z / 2)),
            depth: e.depth + 1,
            routed: true,
          });
        if (z) mods.push(`G11:${z}`);
      }
    }
    if (host && n > 0) {
      if (main)
        for (const [os, op] of order) {
          if (!active(os, op)) continue;
          const id = teams[os][op].id,
            L = ledgers[os][op],
            a = target(os, op),
            b = target(os, op, 1);
          if (os === ts) {
            if (id === "SL3" && op === t && once(os, op, "hermitLoss"))
              route(Math.min(n, 4), ts, a, "SL3-loss", os, op);
            if (id === "LU1" && a === t && once(os, op, "protect"))
              route(n, ts, op, "LU1", os, op);
            if (id === "SL4" && a === t && once(os, op, "sleepDebt"))
              store(Math.min(n, 4), L.debts, "SL4");
            if (id === "LU4" && a === t && once(os, op, "loveDebt"))
              store(Math.min(n, 3), L.debts, "LU4");
            if (id === "LU2" && a === t && mode(os, op) === 1)
              L.gain += route(
                take(os, op, "link", f(n / 2), 4),
                ts,
                b,
                "LU2",
                os,
                op,
              );
          } else if (id === "GL5" && b === t && once(os, op, "bitter")) {
            const z = Math.min(n, 3);
            n -= z;
            L.food[1] += z;
            mods.push("GL5:eaten");
          }
        }
      if (main) {
        for (let q = 0; q < 3; q++)
          if (
            q !== t &&
            gid(ts, q) === "G18" &&
            extreme(ts, q) === t &&
            once(ts, q, "lightning")
          ) {
            const z = n;
            n = 0;
            recordBlocked(ts, Math.min(1, z));
            if (z) {
              blockedByTicket.set(
                e.ticket,
                (blockedByTicket.get(e.ticket) || 0) + 1,
              );
              if (!e.fieldChain) fieldQueue.push(...terrain.blocked(ts, q, 1));
            }
            diverted += execute({
              ...e,
              target: q,
              amount: Math.max(0, z - 1),
              depth: e.depth + 1,
              routed: true,
            });
            mods.push("G18");
          }
        const g = gid(ts, t);
        if (g === "G06" && once(ts, t, "vent"))
          route(f(n / 2), ts, extreme(ts, t, true), "G06");
        if (g === "G19" && once(ts, t, "net"))
          route(f(n / 2), ts, extreme(ts, t), "G19");
        if (g === "G20" && once(ts, t, "delayLoss")) store(n, delayed, "G20");
      }
      if (!e.fieldChain) block(terrain.guard(ts, t, n), "F6");
      if (card(u.id).basic === "shield" && n > 0 && once(ts, t, "shield"))
        block(1, "shield");
      if (
        active(ts, t, "EN2") &&
        mode(ts, t) === 0 &&
        n > 0 &&
        once(ts, t, "mirror")
      )
        block(n - f(n / 2), "EN2");
      if (
        active(ts, t, "SL2") &&
        mode(ts, t) === 0 &&
        n > 0 &&
        once(ts, t, "giant")
      )
        block(3, "SL2");
      if (gid(ts, t) === "G04") block(n - f(n / 2), "G04");
      if (gid(ts, t) === "G05" && n > 0 && once(ts, t, "screen"))
        block(3, "G05");
      if (gid(ts, t) === "G14" && n > 0 && once(ts, t, "invert")) {
        const z = block(2, "G14");
        bonus(ts, t, t, z, "G14");
      }
    }
    const before = powers[ts][t],
      applied = e.kind === "gain" ? n : Math.min(n, Math.max(0, before));
    powers[ts][t] += e.kind === "gain" ? applied : -applied;
    if (options.trace !== false)
      trace.push({
        ...e,
        proposed: input.amount,
        applied,
        before,
        after: powers[ts][t],
        modifiers: mods,
      });
    if (mods.length) note(ts, t, mods.join(","));
    if (main && applied > 0) {
      for (const [os, op] of order) {
        if (!active(os, op)) continue;
        const id = teams[os][op].id,
          L = ledgers[os][op],
          a = target(os, op),
          b = target(os, op, 1);
        if (id === "PR1" && os !== ts && a === t && e.kind === "gain")
          L.gain = Math.min(4, L.gain + applied);
        if (
          id === "GR4" &&
          os === ts &&
          (a === t || b === t) &&
          e.kind === "gain"
        )
          L.loan[t] = Math.min(8, L.loan[t] + applied);
        if (id === "LU1" && os === ts && op === t && host)
          L.loss = Math.min(4, L.loss + applied);
        if (
          id === "GL4" &&
          os === ts &&
          e.kind === "cost" &&
          e.origin === "skill" &&
          p !== op
        )
          L.blocked = Math.min(4, L.blocked + applied);
        if (id === "WR4" && os === ts && (op === t || a === t) && host) {
          const z = Math.min(applied, 6 - L.loss);
          L.loss += z;
          L.bySource[p] += z;
        }
        if (id === "LU5" && os === ts && (a === t || b === t) && host)
          L.loan[t] = Math.min(3, L.loan[t] + applied);
        if (
          id === "EN4" &&
          e.origin === "skill" &&
          e.kind === "gain" &&
          s === ts
        ) {
          const out =
            s === os && p === a
              ? L.out
              : s !== os && p === b
                ? L.enemyOut
                : null;
          if (out) {
            const z = Math.min(
              applied,
              6 - out.reduce((sum, v) => sum + v.amount, 0),
            );
            if (z > 0) out.push({ ...e, amount: z });
          }
        }
      }
      if (
        e.kind === "gain" &&
        card(u.id).basic === "relay" &&
        s === ts &&
        p !== t &&
        once(ts, t, "relay")
      )
        execute({
          ...packet(ts, t, ts, t, 1, "gain", "relay", "basic"),
          depth: e.depth + 1,
          fieldChain: e.fieldChain,
        });
      if (
        e.kind === "gain" &&
        e.origin === "skill" &&
        gid(s, p) === "G08" &&
        take(s, p, "echo", 1, 3)
      )
        bonus(s, p, extreme(s, p), 1, "G08");
      if (e.kind === "cost" && e.origin === "skill")
        for (let q = 0; q < 3; q++)
          if (gid(ts, q) === "G21") take(ts, q, "recycle", applied, 2);
    }
    if (host && applied > 0) {
      if (gid(ts, t) === "G10" && once(ts, t, "reflect"))
        execute({
          ...packet(ts, t, s, p, 2, "loss", "G10", "gear"),
          phase: e.phase,
          depth: e.depth + 1,
          fieldChain: e.fieldChain,
        });
      if (e.origin === "skill" && gid(s, p) === "G07")
        bonus(s, p, p, take(s, p, "siphon", f(applied / 2), 3), "G07");
    }
    if (applied > 0 && !e.fieldChain) {
      if (e.kind === "gain")
        fieldQueue.push(...terrain.arrived(ts, t, s, p, applied));
      if (e.kind === "cost" && e.origin === "skill")
        terrain.paid(s, p, applied);
    }
    const combined = new Map<string, (typeof fieldQueue)[number]>();
    for (const b of fieldQueue) {
      const key = `${b.seat}:${b.source}:${b.target}:${b.label}`,
        old = combined.get(key);
      if (old) old.amount += b.amount;
      else combined.set(key, { ...b });
    }
    for (const b of combined.values())
      execute({
        ...packet(
          b.seat,
          b.source,
          b.seat,
          b.target,
          b.amount,
          "gain",
          b.label,
          "field",
        ),
        phase: e.phase,
        depth: e.depth + 1,
        fieldChain: true,
      });
    return applied + diverted;
  }
  const run = (
    s: Seat,
    p: number,
    ts: Seat,
    t: number,
    n: number,
    k: Event["kind"],
  ) => execute(packet(s, p, ts, t, n, k));
  for (const [s, p] of order)
    if (active(s, p)) {
      const id = teams[s][p].id,
        a = target(s, p),
        m = mode(s, p),
        op = other(s);
      const add = (ts: Seat, t: number, n: number, k: Event["kind"]) =>
        primary.push(packet(s, p, ts, t, n, k));
      const cost = (t: number, n: number) => add(s, t, n, "cost"),
        gain = (t: number, n: number) => add(s, t, n, "gain");
      const move = (from: number, to: number, n: number, extra = 0) => {
        const key = `${s}:${p}:${primary.length}`;
        primary.push({
          ...packet(s, p, s, from, n, "cost"),
          transferDebit: true,
          transferKey: key,
        });
        primary.push({
          ...packet(s, p, s, to, n, "gain"),
          transferKey: key,
          receiptBonus: extra,
        });
      };
      switch (id) {
        case "WR1":
          cost(p, 1);
          add(op, a, 3, "loss");
          break;
        case "WR2":
          move(p, a, 2, 2);
          break;
        case "WR3":
          others(p).forEach((q, i) => move(q, p, 2, i === 0 ? 1 : 0));
          break;
        case "GR1":
          move(a, p, 3, 1);
          break;
        case "GR2":
          others(p).forEach((q) => move(p, q, 1, 1));
          break;
        case "GR3":
          others(p).forEach((q, i) => move(q, p, 1, i === 0 ? 1 : 0));
          break;
        case "GL1":
          primary.push({
            ...packet(s, p, op, a, 2, "loss"),
            transferDebit: true,
          });
          break;
        case "GL2": {
          const hi = snapshot[s][p] >= snapshot[s][a] ? p : a,
            lo = hi === p ? a : p,
            n = f(Math.abs(snapshot[s][p] - snapshot[s][a]) / 2);
          move(hi, lo, n);
          break;
        }
        case "GL3":
          primary.push({
            ...packet(s, p, s, p, 2, "cost"),
            transferKey: `late:${s}:${p}`,
            transferDebit: true,
          });
          break;
        case "EN1":
        case "EN3":
        case "SL3":
        case "PR1":
        case "PR2":
        case "PR3":
        case "LU1":
        case "GL4":
        case "EN4":
        case "SL4":
        case "LU5":
          cost(p, 1);
          break;
        case "EN2":
          if (m) {
            gain(p, 3);
            cost(p, 1);
          }
          break;
        case "SL1":
          cost(p, 2);
          break;
        case "SL2":
          if (m) others(p).forEach((q) => move(q, p, 1, 1));
          break;
        case "LU2":
          break;
        case "LU3":
        case "LU4":
          cost(p, 2);
          break;
        case "WR4":
        case "GL5":
          move(p, a, 2);
          break;
        case "GR4":
          cost(p, 2);
          gain(a, 2);
          gain(target(s, p, 1), 2);
          break;
        default:
          throw Error("Missing skill " + id);
      }
    }
  // Paid costs, then positive effects, then hostile effects. Stable source position within a band.
  primary.sort(
    (a, b) =>
      ["cost", "gain", "loss"].indexOf(a.kind) -
      ["cost", "gain", "loss"].indexOf(b.kind),
  );
  for (const e of primary) {
    if (e.transferKey && e.kind === "gain")
      e.amount =
        terrain.transfer(transferred.get(e.transferKey) || 0) +
        (e.receiptBonus || 0);
    const n = execute(e);
    if (e.transferKey && e.kind === "cost") transferred.set(e.transferKey, n);
    if (e.label === "GL1" && e.kind === "loss")
      run(e.seat, e.source, e.seat, e.source, terrain.transfer(n), "gain");
  }
  phase = "tail";
  for (const e of delayed) execute(e);
  for (const [s, p] of order) {
    const get = (key: string) => counts.get(`${s}:${p}:${key}`) || 0;
    if (get("capacitor"))
      execute(
        packet(s, p, s, p, f(get("capacitor") / 2), "gain", "G09", "gear"),
      );
    if (get("reserve"))
      execute(
        packet(s, p, s, p, f(get("reserve") / 2), "gain", "reserve", "basic"),
      );
    if (get("recycle"))
      execute(packet(s, p, s, p, get("recycle"), "gain", "G21", "gear"));
  }
  for (const [s, p] of order)
    if (active(s, p)) {
      const id = teams[s][p].id,
        L = ledgers[s][p],
        a = target(s, p),
        b = target(s, p, 1),
        m = mode(s, p),
        op = other(s);
      const gain = (q: number, n: number) => run(s, p, s, q, n, "gain"),
        cost = (q: number, n: number) => run(s, p, s, q, n, "cost"),
        loss = (q: number, n: number) => run(s, p, op, q, n, "loss");
      const debit = (ts: Seat, q: number, n: number) =>
        execute({
          ...packet(s, p, ts, q, n, ts === s ? "cost" : "loss"),
          transferDebit: true,
        });
      switch (id) {
        case "GL3":
          gain(a, terrain.transfer(transferred.get(`late:${s}:${p}`) || 0) + 1);
          break;
        case "SL1":
          gain(p, 4);
          break;
        case "PR1":
          loss(a, L.gain);
          break;
        case "LU1":
          loss(b, L.loss);
          break;
        case "LU2":
          gain(a, f(L.gain / 2));
          break;
        case "LU3":
          if (L.gain) gain(b, terrain.transfer(L.gain) + 1);
          break;
        case "GL4":
          gain(p, f(L.blocked / 2));
          gain(a, L.blocked - f(L.blocked / 2));
          break;
        case "WR4": {
          let paid = 0,
            blocked = 0;
          const collect = (q: number, n: number) => {
            const ticket = ++serial;
            paid += execute({ ...packet(s, p, op, q, n, "loss"), ticket });
            blocked += blockedByTicket.get(ticket) || 0;
          };
          if (m) for (let q = 0; q < 3; q++) collect(q, L.bySource[q]);
          else collect(b, L.loss);
          gain(p, Math.min(3, f(paid / 2)));
          cost(p, f(blocked / 2));
          break;
        }
        case "GR4": {
          const due = [
              Math.min(4, f(L.loan[a] / 2)),
              Math.min(4, f(L.loan[b] / 2)),
            ],
            cash = debit(s, a, due[0]) + debit(s, b, due[1]);
          if (cash) {
            if (m) {
              gain(b, terrain.transfer(cash));
              gain(a, f(cash / 2));
            } else gain(p, terrain.transfer(cash) + 1);
          }
          break;
        }
        case "GL5": {
          const n = L.food[0] + L.food[1],
            both = L.food.every((v) => v > 0);
          if (m) {
            loss(b, n);
            if (both) gain(a, 2);
          } else {
            gain(p, n + (both ? 2 : 0));
            gain(a, f(L.food[1] / 2));
          }
          if (n && !both) cost(p, 1);
          break;
        }
        case "EN4": {
          const selected = m ? L.out : L.enemyOut;
          if (!selected.length) break;
          cost(p, new Set(selected.map((e) => e.target)).size - 1);
          let copied = 0;
          const biggest = selected.reduce(
            (best, e, i) => (e.amount > selected[best].amount ? i : best),
            0,
          );
          selected.forEach((e, i) => {
            if (m) {
              if (i === biggest) loss(b, e.amount);
              else gain(p, e.amount);
            } else copied += gain(2 - e.target, e.amount);
          });
          if (!m) loss(b, f(copied / 2));
          break;
        }
        case "SL4": {
          const pay = (q: number) =>
            L.debts.reduce(
              (n, e) =>
                n + execute({ ...e, phase: "tail", targetSeat: s, target: q }),
              0,
            );
          const receive = (q: number) =>
            L.gifts.reduce(
              (n, e) =>
                n +
                (execute({
                  ...e,
                  phase: "tail",
                  targetSeat: s,
                  target: q,
                  amount:
                    q === e.target ? e.amount : terrain.transfer(e.amount),
                }) > 0
                  ? 1
                  : 0),
              0,
            );
          if (m) {
            const n = receive(a);
            pay(b);
            gain(b, Math.min(2, n));
          } else {
            const n = pay(a);
            receive(b);
            gain(a, Math.min(2, f(n / 2)));
          }
          break;
        }
        case "PR3": {
          const tribute = () => {
            const standard = powers[s][p],
              dues = [
                Math.min(3, Math.max(0, powers[s][a] - standard)),
                Math.min(3, Math.max(0, powers[op][b] - standard)),
              ];
            gain(
              p,
              terrain.transfer(debit(s, a, dues[0]) + debit(op, b, dues[1])),
            );
          };
          const crown = () =>
            gain(
              a,
              terrain.transfer(
                debit(
                  s,
                  p,
                  Math.min(
                    3,
                    Math.max(0, f((powers[s][p] - powers[s][a]) / 2)),
                  ),
                ),
              ),
            );
          if (m) {
            crown();
            tribute();
          } else {
            tribute();
            crown();
          }
          break;
        }
        case "LU4": {
          const receive = (q: number) =>
            L.gifts.reduce(
              (n, e) =>
                n +
                execute({
                  ...e,
                  phase: "tail",
                  targetSeat: s,
                  target: q,
                  amount: terrain.transfer(e.amount),
                }),
              0,
            );
          const pay = (ts: Seat, q: number) =>
            L.debts.reduce(
              (n, e) =>
                n +
                execute({
                  ...e,
                  phase: "tail",
                  targetSeat: ts,
                  target: q,
                  ...(ts === op
                    ? { seat: s, source: p, origin: "skill" as const }
                    : {}),
                }),
              0,
            );
          if (m) {
            const g = receive(a),
              d = pay(s, p),
              proposed = Math.min(5, d + f(g / 2)),
              ticket = ++serial;
            execute({ ...packet(s, p, op, b, proposed, "loss"), ticket });
            cost(a, f((blockedByTicket.get(ticket) || 0) / 2));
          } else {
            const g = receive(p),
              d = pay(op, b);
            if (g > d) gain(a, Math.min(2, g - d));
            else cost(p, f((d - g) / 2));
          }
          break;
        }
        case "LU5": {
          if (m) {
            gain(a, terrain.transfer(f(L.gain / 2)));
            gain(b, terrain.transfer(L.gain - f(L.gain / 2)));
            gain(p, Math.max(L.loan[a], L.loan[b]));
          } else {
            const first = L.loan[a] >= L.loan[b] ? a : b,
              second = first === a ? b : a,
              n = Math.min(L.gain, L.loan[first]);
            gain(first, terrain.transfer(n));
            gain(second, terrain.transfer(L.gain - n));
          }
          break;
        }
      }
    }
  const lanes = powers[0].map((v, i) =>
    v === powers[1][i] ? null : v > powers[1][i] ? 0 : 1,
  ) as (Seat | null)[];
  const wins = [
    lanes.filter((s) => s === 0).length,
    lanes.filter((s) => s === 1).length,
  ];
  return {
    powers,
    winner: wins[0] === wins[1] ? null : wins[0] > wins[1] ? 0 : 1,
    lanes,
    trace,
    interactions,
  };
}
