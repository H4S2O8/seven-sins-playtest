import {
  UNITS,
  UNIT_BY_ID,
  CARDS,
  RULES,
  PLEDGES,
  EFFECTS,
  KEYWORDS,
  CONTENT,
  findContent,
} from "./content.js";
import {
  rng,
  shuffle,
  newGame,
  makeUnit,
  living,
  population,
  stats,
  auctionResult,
  ruleContest,
  autoDeploy,
  availableRules,
  botPlan,
  createBattle,
  stepBattle,
  simulate,
  settle,
  slotPosition,
  validDeployment,
  MAIN_CAP,
  POP_CAP,
  resolveRule,
} from "./engine.js";
import { ASSETS, portrait, drawArena, drawEntity, drawBattle } from "./art.js";
const app = document.querySelector("#app"),
  modal = document.querySelector("#modal");
const SAVE = "oath-arena-v1";
let g = null,
  selectedUnit = null,
  selectedNomination = null,
  battle = null,
  speed = 1,
  paused = false,
  frame = 0,
  last = 0,
  accumulator = 0,
  tab = "units",
  query = "",
  muted = true,
  audioCtx = null;
const esc = (s) =>
  String(s ?? "").replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const byId = (list, id) => list.find((x) => x.id === id);
const btn = (text, action, cls = "button", extra = "") =>
  `<button class="${cls}" data-action="${action}" ${extra}>${text}</button>`;
function toast(s) {
  const e = document.querySelector("#toast");
  e.textContent = s;
  e.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => e.classList.remove("show"), 2600);
}
function sound(freq = 440) {
  if (muted) return;
  if (ASSETS.audio.click) {
    const a = new Audio(ASSETS.audio.click);
    a.volume = 0.25;
    a.play().catch(() => {});
    return;
  }
  try {
    audioCtx ??= new AudioContext();
    const o = audioCtx.createOscillator(),
      v = audioCtx.createGain();
    o.type = "sine";
    o.frequency.setValueAtTime(freq, audioCtx.currentTime);
    o.frequency.exponentialRampToValueAtTime(
      freq * 0.5,
      audioCtx.currentTime + 0.12,
    );
    v.gain.setValueAtTime(0.045, audioCtx.currentTime);
    v.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.15);
    o.connect(v).connect(audioCtx.destination);
    o.start();
    o.stop(audioCtx.currentTime + 0.16);
  } catch {}
}
function save() {
  if (g)
    try {
      localStorage.setItem(SAVE, JSON.stringify(g));
    } catch {
      toast("浏览器未允许保存；本局仍可继续。");
    }
}
function random(offset = 0) {
  return rng(
    g.seed + g.round * 997 + g.auctionIndex * 191 + g.auctionTurn * 37 + offset,
  );
}
const typeName = {
  units: "兵种",
  cards: "效果牌",
  pledges: "承诺",
  rules: "规则",
};
function prepareAuction() {
  const kind = g.auctionKind;
  g.auctionPool = shuffle(CONTENT[kind], random(45))
    .slice(0, 10)
    .map((x) => x.id);
  if (g.tutorial && kind === "units")
    g.auctionPool = [
      "u1",
      "u2",
      "u3",
      "u4",
      "u6",
      "u9",
      "u10",
      "u12",
      "u16",
      "u25",
    ];
  g.auctionTurn = 0;
  g.auctionState = "bid";
  prepareBotBid();
}
function prepareBotBid() {
  const r = random(302);
  const remaining = 15 - g.auctionIndex * 5 - g.auctionTurn;
  g.botBid = Math.min(
    g.money[1],
    Math.floor(
      r() * Math.min(7, Math.max(2, (g.money[1] / Math.max(1, remaining)) * 2)),
    ),
  );
}
function unitValue(id, side) {
  const u = UNIT_BY_ID[id],
    roster = g.sides[side].units.map(stats);
  return (
    u.atk / u.interval +
    u.hp * 0.15 -
    u.pop * 4 +
    (roster.some((x) => x.tags.includes("heal"))
      ? 0
      : u.tags.includes("heal")
        ? 14
        : 0) +
    (roster.some((x) => x.range > 160) ? 0 : u.range > 160 ? 12 : 0)
  );
}
function botPick() {
  const r = random(704);
  let id;
  if (g.auctionKind === "units")
    id = [...g.auctionPool].sort(
      (a, b) => unitValue(b, 1) - unitValue(a, 1),
    )[0];
  else id = g.auctionPool[Math.floor(r() * g.auctionPool.length)];
  acquire(1, id);
  return id;
}
function acquire(side, id) {
  g.auctionPool = g.auctionPool.filter((x) => x !== id);
  if (g.auctionKind === "units")
    g.sides[side].units.push(makeUnit(id, `${side}-${id}`));
  else g.sides[side][g.auctionKind].push(id);
}
function bid() {
  const n = Number(document.querySelector("#bid").value);
  if (!Number.isInteger(n) || n < 0 || n > g.money[0])
    return toast("出价必须是余额以内的非负整数。");
  const r = auctionResult([n, g.botBid], g.priority);
  g.priority = r.priority;
  g.money[r.winner] -= r.cost;
  g.pickWinner = r.winner;
  g.auctionState = "pick";
  g.lastMessage = `你出 ${n}，对手出 ${g.botBid}。${r.winner === 0 ? "你" : "对手"}支付 ${r.cost}，获得先选权。`;
  if (r.winner === 1) {
    const id = botPick();
    g.lastMessage += ` 对手取走「${findContent(id).name}」，现在轮到你。`;
  }
  sound(390);
  save();
  render();
}
function chooseAuction(id) {
  if (g.auctionState !== "pick" || !g.auctionPool.includes(id)) return;
  acquire(0, id);
  let msg = `你获得「${findContent(id).name}」。`;
  if (g.pickWinner === 0) {
    const b = botPick();
    msg += ` 对手获得「${findContent(b).name}」。`;
  }
  g.history.push(msg);
  g.lastMessage = msg;
  g.auctionTurn++;
  if (g.auctionTurn >= 5) {
    g.auctionIndex++;
    if (g.auctionIndex >= 3) {
      beginRound();
      return;
    }
    g.auctionKind = ["units", "cards", "pledges"][g.auctionIndex];
    prepareAuction();
  } else {
    g.auctionState = "bid";
    prepareBotBid();
  }
  save();
  render();
}
function fastDraft() {
  let safe = 0;
  while (g.phase === "auction" && safe++ < 16) {
    if (g.auctionState === "bid") {
      const r = auctionResult([0, g.botBid], g.priority);
      g.priority = r.priority;
      g.money[r.winner] -= r.cost;
      g.pickWinner = r.winner;
      g.auctionState = "pick";
      if (r.winner === 1) botPick();
    }
    const id =
      g.auctionKind === "units"
        ? [...g.auctionPool].sort(
            (a, b) => unitValue(b, 0) - unitValue(a, 0),
          )[0]
        : g.auctionPool[0];
    chooseAuction(id);
  }
  toast("已用零出价完成剩余征募，余额保留给规则竞拍。");
}
function beginRound() {
  g.phase = "main";
  g.deployed = [[], autoDeploy(g.sides[1])];
  g.locked = [];
  g.rule = null;
  g.selectedCards = [null, null];
  g.selectedPledges = [null, null];
  g.nominations = [null, null];
  g.effectTargets = [null, null];
  g.lastMessage = "每轮重新选人布阵，伤亡不会重置。";
  selectedUnit = null;
  save();
  render();
}
function place(slot) {
  if (!selectedUnit) return toast("先在下方选择一个存活兵种，再点己方位置。");
  if (!["main", "reserve"].includes(g.phase)) return;
  if (g.locked.includes(selectedUnit)) return toast("主阵已经锁定，不能修改。");
  const src = g.sides[0].units.find((u) => u.uid === selectedUnit),
    old = g.deployed[0].find((u) => u.uid === selectedUnit),
    occupant = g.deployed[0].find((u) => u.slot === slot);
  if (occupant && g.locked.includes(occupant.uid))
    return toast("这个位置属于锁定主阵。");
  const list = g.deployed[0].filter(
    (u) => u.uid !== selectedUnit && u.slot !== slot,
  );
  const next = {
    ...src,
    slot,
    mode: old?.mode || (stats(src).range >= 175 ? "stand" : "move"),
  };
  const cap = g.phase === "main" ? MAIN_CAP : POP_CAP;
  if (population([...list, next]) > cap)
    return toast(`这一阶段最多 ${cap} 人口。`);
  g.deployed[0] = [...list, next];
  save();
  render();
  sound(550);
}
function lockMain() {
  if (!validDeployment(g.deployed[0], MAIN_CAP))
    return toast("至少部署一个单位，且主阵不超过4人口。");
  g.locked = g.deployed[0].map((u) => u.uid);
  g.rulePool = availableRules(g.deployed, random(902)).map((r) => r.id);
  g.botPlan = botPlan(
    g.sides[1],
    g.deployed[0],
    g.deployed[1],
    g.round,
    g.cardReady[1],
    random(320),
  );
  g.selectedCards[1] = g.botPlan.card;
  g.selectedPledges[1] =
    g.sides[1].pledges.find((id) => {
      const p = byId(PLEDGES, id);
      const m = g.botPlan.metrics[1];
      return p.direction * (m[p.metric] - p.threshold) >= 0;
    }) || null;
  g.effectTargets[1] = g.deployed[1][0]?.uid;
  g.phase = "commit";
  selectedUnit = null;
  save();
  render();
}
function lockCard() {
  if (
    !g.selectedCards[0] &&
    g.sides[0].cards.some((id) => (g.cardReady[0][id] || 0) <= g.round)
  )
    return toast("选择一张本轮暗牌。");
  g.effectTargets[0] =
    document.querySelector("#effect-target")?.value || g.deployed[0][0].uid;
  const scored = g.rulePool.map((id) => {
    const r = byId(RULES, id),
      out = resolveRule(r, g.botPlan.metrics)[1];
    return {
      id,
      score:
        (out === g.botPlan.desired ? 2 : 0) +
        random(Number(id.slice(1)) + 60)(),
    };
  });
  g.nominations[1] = scored.sort((a, b) => b.score - a.score)[0].id;
  g.ruleBid = Math.min(
    g.money[1],
    Math.floor(random(800)() * Math.min(8, g.money[1] / 2 + 1)),
  );
  g.phase = "nominate";
  selectedNomination = null;
  save();
  render();
}
function nominate() {
  if (!selectedNomination) return toast("先选一条你希望生效的规则。");
  g.nominations[0] = selectedNomination;
  if (g.nominations[0] === g.nominations[1]) {
    g.rule = g.nominations[0];
    g.lastMessage = "双方选择同一条规则，不付钱，直接生效。";
    prepareReserve();
  } else {
    g.phase = "contest";
    save();
    render();
  }
}
function contest() {
  const n = Number(document.querySelector("#bid").value);
  if (!Number.isInteger(n) || n < 0 || n > g.money[0])
    return toast("出价超出余额或格式不正确。");
  const r = ruleContest(g.nominations, [n, g.ruleBid], g.priority);
  g.priority = r.priority;
  g.rule = r.rule;
  if (r.winner !== null) g.money[r.winner] -= r.cost;
  g.lastMessage = `规则暗拍：你出 ${n}，对手出 ${g.ruleBid}。${r.winner === 0 ? "你" : "对手"}支付 ${r.cost}，规则确定。`;
  prepareReserve();
}
function prepareReserve() {
  // Opponent reserves depend only on public mains, rule and its own hidden card.
  const base = g.deployed[1];
  const candidates = ["balanced", "defense"].map((style) =>
    autoDeploy(g.sides[1], POP_CAP, base, style),
  );
  const lockedIds = new Set(base.map((u) => u.uid));
  const freeSlots = Array.from({ length: 6 }, (_, i) => i).filter(
    (i) => !base.some((u) => u.slot === i),
  );
  for (const unit of living(g.sides[1]).filter((u) => !lockedIds.has(u.uid))) {
    if (population(base) + stats(unit).pop > POP_CAP) continue;
    for (const slot of freeSlots)
      for (const mode of ["move", "stand"])
        candidates.push([...base, { ...unit, slot, mode }]);
  }
  const rule = byId(RULES, g.rule);
  let best = candidates[0],
    score = -Infinity;
  for (const c of candidates) {
    const f = simulate([g.deployed[0], c], { round: g.round });
    const match = resolveRule(rule, f.metrics)[1] === g.botPlan.desired;
    const value = f.metrics[1].damage - f.metrics[0].damage + (match ? 35 : 0);
    if (value > score) {
      score = value;
      best = c;
    }
  }
  g.botFinal = best;
  g.phase = "reserve";
  selectedUnit = null;
  save();
  render();
}
function startFight() {
  if (!validDeployment(g.deployed[0])) return toast("需要合法的上场阵容。");
  g.deployed[1] = g.botFinal;
  g.phase = "battle";
  battle = createBattle(g.deployed, { round: g.round });
  paused = false;
  accumulator = 0;
  last = 0;
  render();
  sound(160);
  cancelAnimationFrame(frame);
  frame = requestAnimationFrame(tick);
}
function tick(t) {
  if (!battle || g.phase !== "battle") return;
  const dt = last ? Math.min(0.08, (t - last) / 1000) : 0;
  last = t;
  if (!paused) accumulator += dt * speed;
  while (accumulator >= 0.05 && !battle.ended) {
    stepBattle(battle, 0.05);
    accumulator -= 0.05;
  }
  const cv = document.querySelector("#arena");
  if (cv) drawBattle(cv.getContext("2d"), battle);
  const timer = document.querySelector("#timer");
  if (timer)
    timer.textContent = `${Math.max(0, 18 - battle.time).toFixed(1)} s`;
  const clock = document.querySelector("#clock-fill");
  if (clock) clock.style.width = `${(1 - battle.time / 18) * 100}%`;
  if (battle.ended) {
    g.lastResult = settle(g, battle, g.effectTargets);
    g.replay = battle.frames;
    save();
    sound(250);
    render();
    return;
  }
  frame = requestAnimationFrame(tick);
}
function start(tutorial = false) {
  cancelAnimationFrame(frame);
  const supplied = Number(new URLSearchParams(location.search).get("seed"));
  g = newGame(supplied || Date.now() >>> 0, tutorial);
  prepareAuction();
  save();
  render();
}
function heading() {
  return `<header><a class="brand" href="#" data-action="home"><span class="brand-mark">◈</span><span>逆誓竞技场<small>OATH / FALL</small></span></a><nav>${btn("图鉴 · 180", "catalog", "text-btn")}${btn("怎么玩", "help", "text-btn")}${btn(muted ? "声音：关" : "声音：开", "sound", "text-btn")}${g ? btn("保存退出", "home", "text-btn") : ""}</nav></header>`;
}
function hud() {
  if (!g) return "";
  return `<div class="hud"><div><span class="eyebrow">${g.phase === "auction" ? "战前征募" : "第 " + g.round + " 次交锋"}</span><strong>${g.phase === "auction" ? "同样的钱，不同的选择" : "杀光对方整支军队，才是胜利"}</strong></div><div class="wallet you"><small>你的筹码</small><b>${g.money[0]}</b><span>存活 ${living(g.sides[0]).length} / ${g.sides[0].units.length}</span></div><div class="wallet foe"><small>对手筹码</small><b>${g.money[1]}</b><span>存活 ${living(g.sides[1]).length} / ${g.sides[1].units.length}</span></div><div class="priority"><small>平价优先</small><b>${g.priority === 0 ? "你" : "对手"}</b></div></div>`;
}
const guides = {
  auction: [
    "01 / 先买选择权",
    "双方各有40筹码，整局不补钱。暗拍的是“先选哪张”的权利：只有赢家付钱，双方仍各取一张。先拍兵种，再拍效果牌，最后拍承诺。",
    "输入出价，点“锁定出价”；出价0也合法。然后点击想要的牌。",
  ],
  main: [
    "02 / 把主阵放上去",
    "你们都知道彼此的全部兵种，但主阵要同时公开。这里先放最多4人口；主阵锁定后，本轮不能换人、挪位或改变移动方式。",
    "先点下方兵种，再点场上的己方位置。选中的兵可以切换“移动／站定”。也可先用建议布阵再调整。",
  ],
  commit: [
    "03 / 想要哪一面？",
    "暗牌有成功、失败两个效果。成功不等于赢，失败也不等于死兵。效果在打完以后才结算，强化从下一场起生效。承诺则公开给对方看，达成才有额外收益。",
    "选择一张暗牌和一个收益对象；可选一张公开承诺。对手已经锁牌，不会偷看你的选择。",
  ],
  nominate: [
    "04 / 争什么算成功",
    "主阵已经公开。双方独立按同一规则判定，所以可以同时成功或同时失败。选择同一条规则免费；选择不同，才暗拍哪一条生效。",
    "从10条候选中选一条，然后揭晓提名。请读清“不低于”和“不高于”。",
  ],
  contest: [
    "05 / 分歧才花钱",
    "只在双方提名的两条规则之间竞拍。价高者付自己的出价，另一方不付钱。平价用轮转优先权，出价前就能看到归谁。",
    "看看双方的规则，再决定出多少。留钱给后续交锋也是一种策略。",
  ],
  reserve: [
    "06 / 最后的后手",
    "双方用剩余人口秘密补阵，总计不超过6。先前主阵不能修改。你知道对手有哪些预备兵，但不知道这次补哪一个。",
    "可以补兵，也可以直接开战。站定兵不追人、也不发动冲锋；移动兵按自己的行为接敌。",
  ],
  battle: [
    "07 / 看清它为什么发生",
    "战斗自动进行18秒，没有随机暴击。前后排是实际位置，不是无敌屏障。圣盾挡一次伤害，护卫会替身旁队友受伤。",
    "可以暂停观察或加速。战斗中不能重新布阵。",
  ],
  result: [
    "08 / 效果到手，不代表赚了",
    "先固定战场数据，再亮暗牌和结算承诺。伤亡永久保留，伤者可以被治疗；本轮死者不会因普通治疗复活。强化期限即使坐预备席也会流逝。",
    "核对判定数值和实际获得的效果。下一轮重新上场，猜对手会如何针对你的公开强化。",
  ],
};
function guide() {
  if (!g?.tutorial) return "";
  const h = guides[g.phase];
  if (!h) return "";
  return `<section class="guide"><span class="guide-number">${h[0]}</span><div><strong>${h[1]}</strong><p>${h[2]}</p></div>${btn("关闭引导", "tutorial-off", "text-btn")}</section>`;
}
function heatNotice() {
  if (!g || g.phase === "auction") return "";
  const n = Math.max(0, g.round - 4);
  return `<div class="heat-note">${n ? `激战升温 ${n}：本场攻击 +${n * 15}%，战斗内治疗 −${Math.min(80, n * 10)}%。` : "激战升温将在第5次交锋开始：逐步提高攻击、降低战斗内治疗，防止无限拖局。"} 仍以消灭全部兵力决定胜负。</div>`;
}
function unitCard(
  u,
  {
    instance = null,
    action = "inspect",
    selected = false,
    disabled = false,
    compact = false,
  } = {},
) {
  const s = instance ? stats(instance) : u;
  return `<button class="unit-card ${compact ? "compact" : ""} ${selected ? "selected" : ""} ${disabled ? "dead" : ""}" data-action="${action}" data-id="${instance?.uid || u.id}" ${disabled ? "disabled" : ""}><span class="pop-badge">${u.pop}<small>人口</small></span>${portrait(u, compact ? 70 : 112)}<h3>${u.name}</h3><div class="unit-stats"><span>♥ ${instance ? Math.ceil(instance.hp) : u.hp}</span><span>⚔ ${Math.round(s.atk)}</span><span>↗ ${s.range}</span></div><p class="tagline">${s.tags.map((t) => KEYWORDS[t]?.split("：")[0] || t).join(" · ")}</p>${instance?.buffs?.length ? `<p class="buffs">${instance.buffs.map((b) => `${EFFECTS[b.key].name} ${b.left}场`).join(" · ")}</p>` : ""}${!compact ? `<p class="flavor">${u.flavor}</p>` : ""}</button>`;
}
function effectCard(c, action = "inspect", selected = false, disabled = false) {
  return `<button class="effect-card ${selected ? "selected" : ""}" data-action="${action}" data-id="${c.id}" ${disabled ? "disabled" : ""}><div class="card-top"><span>秘仪 / ${c.id.toUpperCase()}</span><span>◈</span></div><h3>${c.name}</h3><div class="effect success"><b>成功</b><p>${EFFECTS[c.success].text}</p></div><div class="effect failure"><b>失败</b><p>${EFFECTS[c.failure].text}</p></div><small>指定对象 · 群体效果除外${disabled ? " · 休息中" : ""}</small></button>`;
}
function pledgeCard(p, action = "inspect", selected = false) {
  return `<button class="pledge-card ${selected ? "selected" : ""}" data-action="${action}" data-id="${p.id}"><div class="card-top"><span>公开承诺 / ${p.id.toUpperCase()}</span><span>✧</span></div><h3>${p.name}</h3><p>${p.description}</p><small>一次性 · 未达成也会消耗 · 可以不承诺</small></button>`;
}
function ruleCard(r, action = "inspect", selected = false) {
  return `<button class="rule-card ${selected ? "selected" : ""}" data-action="${action}" data-id="${r.id}"><span class="card-top">共同法则 / ${r.id.toUpperCase()}<b>${r.direction === 1 ? "≥" : "≤"}</b></span><h3>${r.name}</h3><p>${r.description}</p><small>关联：${r.counter}</small></button>`;
}
function itemCard(id, action = "inspect", selected = false) {
  const x = findContent(id);
  if (id[0] === "u") return unitCard(x, { action, selected });
  if (id[0] === "c") return effectCard(x, action, selected);
  if (id[0] === "p") return pledgeCard(x, action, selected);
  return ruleCard(x, action, selected);
}
function drawPreview() {
  const cv = document.querySelector("#arena");
  if (!cv) return;
  const ctx = cv.getContext("2d");
  if (g?.phase === "battle") return;
  drawArena(ctx, 960, 430, 0);
  if (!g || g.phase === "auction") return;
  const lists = g.phase === "result" && battle ? null : g.deployed;
  if (lists) {
    lists.forEach((us, s) => {
      if (s === 1 && g.phase === "main") return;
      us.forEach((u, i) => {
        const p = slotPosition(u.slot, s),
          st = stats(u);
        drawEntity(
          ctx,
          {
            ...st,
            ...p,
            unitId: u.id,
            side: s,
            hp: u.hp,
            maxHp: st.hp,
            face: s === 0 ? 1 : -1,
            marked: i === 0,
            shield: st.shields,
            mode: u.mode,
          },
          0,
        );
      });
    });
  } else drawBattle(ctx, battle);
}
function field(interactive = false) {
  return `<div class="field"><canvas id="arena" width="960" height="430" aria-label="战斗场地，蓝方在左，红方在右"></canvas>${
    interactive
      ? `<div class="slot-layer">${Array.from({ length: 6 }, (_, i) => {
          const p = slotPosition(i, 0),
            u = g.deployed[0].find((u) => u.slot === i),
            locked = u && g.locked.includes(u.uid);
          return `<button class="field-slot ${u ? "filled" : ""} ${locked ? "locked" : ""}" style="left:${p.x / 9.6}%;top:${p.y / 4.3}%" data-action="slot" data-slot="${i}" aria-label="${i < 3 ? "前排" : "后排"}${(i % 3) + 1}${u ? " " + UNIT_BY_ID[u.id].name : ""}">${u ? (locked ? "已锁定" : u.mode === "stand" ? "站定" : "移动") : "＋"}</button>`;
        }).join("")}</div>`
      : ""
  }</div>`;
}
function lobby() {
  return `<main class="lobby"><div class="hero-copy"><span class="eyebrow">AUCTION · FORMATION · BETRAYAL</span><h1>逆誓<span>竞技场</span></h1><p class="hero-sub">你想要的，<br>未必是成功。</p><p class="intro">竞拍军团，暗藏秘仪，争夺定义胜负的法则。<br>让对手猜你想赢哪一面。真正的胜利，仍要靠刀剑。</p><div class="hero-actions">${btn("开始教学对局 <span>↗</span>", "tutorial", "button primary large")}${btn("直接开始对战", "new", "button large")}${localStorage.getItem(SAVE) ? btn("继续上次对局", "continue", "text-btn") : ""}</div><div class="hero-counts"><span><b>30</b>兵种</span><span><b>50</b>双面秘仪</span><span><b>50</b>法则</span><span><b>50</b>承诺</span></div><p class="muted">单人对战电脑 · 一局约15—25分钟 · 自动存档 · 无需登录</p></div><div class="hero-visual"><div class="orbit orbit-a"></div><div class="orbit orbit-b"></div><div class="hero-sigil">◈</div><div class="hero-unit">${portrait(UNITS[4], 340)}</div><div class="floating a"><span>成功</span>获得穿透太阳的力量</div><div class="floating b"><span>失败</span>让黑夜成为你的盾</div><div class="hero-caption">誓约不决定正义。<br>它只决定代价。</div></div></main><footer>原型 0.1 · 美术 / 动画 / 音效可独立替换 · 规则与战斗数据可查</footer>`;
}
function auctionView() {
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">${g.auctionIndex + 1} / 3 · DRAFT</span><h1>${typeName[g.auctionKind]}竞拍 <small>第 ${g.auctionTurn + 1} / 5 次选择</small></h1></div>${btn("零出价完成剩余征募", "fast-draft", "text-btn")}</div><div class="auction-bar"><div><strong>${g.auctionState === "bid" ? "暗拍先选权" : "现在，取走一张"}</strong><p>${g.lastMessage || "每人必得五张。只有争取先选权的人付钱，不是买到一张就让对方空手。"}</p></div>${g.auctionState === "bid" ? `<label>你的出价<input id="bid" aria-label="你的出价" type="number" min="0" max="${g.money[0]}" value="0"></label>${btn("锁定出价", "bid", "button primary")}` : '<span class="selection-note">点击下方卡面领取</span>'}</div><div class="draft-grid">${g.auctionPool.map((id) => itemCard(id, g.auctionState === "pick" ? "pick" : "inspect")).join("")}</div><div class="draft-owned"><div><b>你的征募</b><p>${g.sides[0].units.map((u) => UNIT_BY_ID[u.id].name).join(" / ") || "尚无兵种"}</p><small>效果牌 ${g.sides[0].cards.length}/5 · 承诺 ${g.sides[0].pledges.length}/5</small></div><div><b>对手的征募</b><p>${g.sides[1].units.map((u) => UNIT_BY_ID[u.id].name).join(" / ") || "尚无兵种"}</p><small>效果牌 ${g.sides[1].cards.length}/5 · 承诺 ${g.sides[1].pledges.length}/5</small></div></div></main>`;
}
function roster(side = 0, select = false) {
  return `<div class="roster">${g.sides[side].units.map((u) => unitCard(UNIT_BY_ID[u.id], { instance: u, compact: true, action: select ? "select-unit" : "inspect-unit", selected: u.uid === selectedUnit, disabled: u.hp <= 0 })).join("")}</div>`;
}
function deploymentView() {
  const reserve = g.phase === "reserve",
    u = g.deployed[0].find((u) => u.uid === selectedUnit),
    locked = g.locked.includes(selectedUnit),
    cap = reserve ? 6 : 4;
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">${reserve ? "FINAL DEPLOYMENT" : "OPENING FORMATION"}</span><h1>${reserve ? "补上你的后手" : "部署公开主阵"}</h1></div><span class="population">人口 <b>${population(g.deployed[0])}</b> / ${cap}</span></div>${reserve ? `<div class="notice"><b>${byId(RULES, g.rule).name}</b> ${byId(RULES, g.rule).description}<small>${g.lastMessage}</small></div>` : ""}<div class="battle-layout"><div>${field(true)}<div class="deploy-tools">${btn("建议布阵", "auto", "button")}<span>${u ? UNIT_BY_ID[u.id].name : "选择兵种 → 点击场地位置"}</span>${u && !locked ? `${btn(u.mode === "stand" ? "改为可移动" : "改为站定", "mode", "button small")}${btn("移回预备席", "remove", "text-btn")}` : ""}${locked ? '<span class="muted">主阵已锁定</span>' : ""}</div>${roster(0, true)}</div><aside class="panel"><h3>${reserve ? "对手的公开主阵" : "对手已拥有的兵种"}</h3><p>${reserve ? "他也在秘密补阵。下列主阵不能修改。" : "主阵会同时公开，你目前只能看到他的兵种库。"}</p>${(reserve ? g.deployed[1] : living(g.sides[1])).map((x) => `<div class="enemy-row"><b>${UNIT_BY_ID[x.id].name}</b><span>${UNIT_BY_ID[x.id].pop}人口 · ${Math.ceil(x.hp)}生命${reserve ? " · " + (x.mode === "stand" ? "站定" : "移动") : ""}</span></div>`).join("")}${reserve ? `<div class="public-pledge"><small>对手公开承诺</small><b>${byId(PLEDGES, g.selectedPledges[1])?.name || "本轮不承诺"}</b><p>${byId(PLEDGES, g.selectedPledges[1])?.description || "无额外奖励，也没有额外约束。"}</p></div>` : ""}<div class="aside-bottom"><p>${reserve ? "空人口可以保留，但不能在开打后增援。" : "最先部署的单位会被金环标记，用于部分规则的判定。"}</p>${btn(reserve ? "揭阵 · 开战" : "锁定主阵 · 同时公开", reserve ? "fight" : "lock-main", "button primary wide")}</div></aside></div></main>`;
}
function commitView() {
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">HIDDEN INTENTION</span><h1>你希望哪一面生效？</h1></div>${btn("锁定暗牌与承诺", "lock-card", "button primary")}</div><details class="public-armies"><summary>查看双方已锁定主阵 / 对手拥有的牌</summary>${field(false)}<p>对手拥有：${g.sides[1].cards.map((id) => byId(CARDS, id).name).join("、")}。本轮选择保密。</p></details><div class="target-bar"><label>效果与承诺的收益对象 <select id="effect-target">${living(
    g.sides[0],
  )
    .map(
      (u) =>
        `<option value="${u.uid}">${UNIT_BY_ID[u.id].name} · ${Math.ceil(u.hp)}生命</option>`,
    )
    .join(
      "",
    )}</select></label><small>若对象战死，自动转给存活者中人口最高者；普通治疗不能复活。</small></div><h2>暗放一张秘仪 <small>使用后休息一轮 · 对手不会知道你的选择</small></h2><div class="draft-grid">${g.sides[0].cards.map((id) => effectCard(byId(CARDS, id), "card", id === g.selectedCards[0], (g.cardReady[0][id] || 0) > g.round)).join("")}</div><h2>可选：公开一个承诺 <small>结算后消耗，失败没有奖励</small></h2><div class="pledge-grid">${btn("本轮不作承诺", "no-pledge", `pledge-card ${!g.selectedPledges[0] ? "selected" : ""}`)}${g.sides[0].pledges.map((id) => pledgeCard(byId(PLEDGES, id), "pledge", id === g.selectedPledges[0])).join("")}</div></main>`;
}
function nominateView() {
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">DEFINE THE LAW</span><h1>成功，由什么来定义？</h1><p>同一条规则，分别判定双方。相等时双方成功。词条型规则会根据主阵筛选。</p></div>${btn("锁定提名 · 同时揭晓", "nominate", "button primary")}</div><details><summary>展开已公开主阵</summary>${field(false)}</details><div class="rule-grid">${g.rulePool.map((id) => ruleCard(byId(RULES, id), "nomination", selectedNomination === id)).join("")}</div></main>`;
}
function contestView() {
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">A DISAGREEMENT HAS A PRICE</span><h1>分歧，需要付出代价。</h1></div></div><div class="contest-cards"><div><h2>你的提名</h2>${ruleCard(byId(RULES, g.nominations[0]))}</div><div class="versus">VS</div><div><h2>对手的提名</h2>${ruleCard(byId(RULES, g.nominations[1]))}</div></div><div class="auction-bar"><div><strong>一次暗拍，同时揭晓</strong><p>只有价高者付钱。平价优先：${g.priority === 0 ? "你" : "对手"}。对手的出价已经锁定。</p></div><label>你的出价<input id="bid" aria-label="你的出价" type="number" min="0" max="${g.money[0]}" value="0"></label>${btn("锁定出价 · 决定规则", "contest", "button primary")}</div></main>`;
}
function battleView() {
  const r = byId(RULES, g.rule);
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">BLOOD DECIDES THE REST</span><h1>${r.name}</h1><p>${r.description}</p></div><div class="battle-controls"><b id="timer">18.0 s</b>${btn("暂停", "pause", "button small")}${btn("速度 ×" + speed, "speed", "button small")}</div></div><div class="clock"><i id="clock-fill"></i></div>${field(false)}<div class="battle-foot"><span>蓝方：你 · 红方：对手 · 金环：标记单位</span><span>双方暗牌将在战斗结束后揭晓</span></div></main>`;
}
function resultView() {
  const r = g.lastResult,
    rule = byId(RULES, r.rule),
    over = g.winner !== null;
  return `<main>${hud()}${guide()}<div class="section-head"><div><span class="eyebrow">${over ? "THE LAST WORD" : "REVELATION"}</span><h1>${over ? (g.winner === 0 ? "你的军团，站到了最后。" : g.winner === 1 ? "誓约仍在，军团已尽。" : "双方军团，同归于尽。") : "亮牌。核算这一战的代价。"}</h1></div>${btn(over ? "返回主菜单" : "下一轮 · 重新部署", over ? "home" : "next", "button primary")}</div><div class="verdict"><span>${rule.name}</span><p>${rule.label}：<b class="cyan">你 ${r.metrics[0][rule.metric].toFixed(1)}</b> / <b class="red">对手 ${r.metrics[1][rule.metric].toFixed(1)}</b></p><small>${rule.description} · 以下判定来自效果结算前的数据</small></div><div class="result-columns">${[
    0, 1,
  ]
    .map((s) => {
      const c = byId(CARDS, r.cards[s]),
        p = byId(PLEDGES, r.pledges[s]);
      return `<section class="panel result-side"><div class="result-heading"><h2>${s === 0 ? "你的秘仪" : "对手的秘仪"}</h2><span class="result-label ${r.outcomes[s] ? "success" : "failure"}">${r.outcomes[s] ? "成功面" : "失败面"}生效</span></div>${c ? `<h3 class="reveal-title">${c.name}</h3><p>${EFFECTS[r.outcomes[s] ? c.success : c.failure].text}</p>` : "<p>未使用秘仪</p>"}<div class="loss-list"><strong>本场阵亡</strong><p>${r.losses[s].map((id) => UNIT_BY_ID[g.sides[s].units.find((u) => u.uid === id).id].name).join("、") || "无人阵亡"}</p></div><div class="pledge-result"><strong>${p ? `承诺「${p.name}」${r["pledge" + s] ? "兑现" : "未达成"}` : "未作承诺"}</strong>${p ? `<p>${p.description}</p><small>实际：${r.metrics[s][p.metric].toFixed(1)}</small>` : ""}</div><div class="rewards">${r.rewards
        .filter((x) => x.side === s)
        .map(
          (x) =>
            `<p><b>${EFFECTS[x.key].name}</b> → ${x.ids.map((id) => UNIT_BY_ID[g.sides[s].units.find((u) => u.uid === id).id].name).join("、") || "无存活对象，效果落空"}</p>`,
        )
        .join("")}</div></section>`;
    })
    .join(
      "",
    )}</div><details><summary>逐项核对战场数据</summary><div class="metric-table"><div><b>指标</b><b>你</b><b>对手</b></div>${RULES.filter(
    (_, i) => i % 2 === 0,
  )
    .map(
      (x) =>
        `<div><span>${x.label}</span><span>${r.metrics[0][x.metric].toFixed(1)}</span><span>${r.metrics[1][x.metric].toFixed(1)}</span></div>`,
    )
    .join(
      "",
    )}</div></details><h2>你的剩余军团 <small>已死亡单位不会在下一轮复活</small></h2>${roster(0)}</main>`;
}
function render() {
  app.innerHTML =
    heading() +
    (!g
      ? lobby()
      : g.phase === "auction"
        ? auctionView()
        : ["main", "reserve"].includes(g.phase)
          ? deploymentView()
          : g.phase === "commit"
            ? commitView()
            : g.phase === "nominate"
              ? nominateView()
              : g.phase === "contest"
                ? contestView()
                : g.phase === "battle"
                  ? battleView()
                  : resultView());
  drawPreview();
  if (g && g.phase !== "auction")
    document
      .querySelector(".hud")
      ?.insertAdjacentHTML("afterend", heatNotice());
}
function showHelp() {
  modal.innerHTML = `<div class="modal-head"><h2>先活下来，再谈誓言。</h2>${btn("关闭", "close", "text-btn")}</div><div class="help-body"><p><b>终极目标：</b>消灭对方所有兵种，包括预备席。不是凑分，也不是固定五轮。每场自动战斗最多18秒。</p><ol><li><b>征募：</b>40筹码共用整局，兵种、效果牌、承诺分开竞拍。每组10张，每次双方各拿一张，重复5次。暗拍先选权，赢家付款，输家免费后选。</li><li><b>公开主阵：</b>先部署最多4人口，双方同时公开。点兵种再点场地放下；选择移动或站定。第一名部署单位是规则使用的标记单位。</li><li><b>暗牌：</b>根据主阵选一张效果牌，选择收益对象。成功面与失败面都可能有用。每张牌用后休息一轮。</li><li><b>承诺：</b>可以公开一张额外目标，达成才获得奖励。无论是否达成，使用后都消耗。</li><li><b>规则：</b>从10条候选中暗选。同选一条免费；不同则一次暗拍，赢家的规则生效。比较实际战场数据，双方独立判定，相等双方成功。</li><li><b>补阵：</b>总上场人口最多6。主阵不可变，后手同时揭晓。预备席本场不受攻击。</li><li><b>自动战斗：</b>移动兵自动接敌，站定兵只打射程内敌人。站定不触发冲锋。目标由最近距离、嘲讽等公开行为决定，没有随机暴击。</li><li><b>结算：</b>先固定判定，再亮牌。没有战后直接伤害。治疗不能复活死者，强化在以后战斗兑现。坐预备席也消耗强化期限。下一轮重新布阵，伤亡与剩余生命保留。</li></ol><p>平价时使用公开的轮转优先权；每用一次便交给另一方。钱花完仍可出0，不会卡住游戏。</p><h3>词条说明</h3>${Object.values(
    KEYWORDS,
  )
    .map((t) => `<p>${t}</p>`)
    .join(
      "",
    )}<p class="muted">原型说明：50条规则由25种可核验指标的正反判定构成；部分规则只在主阵出现相关能力时进入候选。候选仍需平衡测试，并不承诺每个战场状态都能翻转判定。电脑没有玩家暗牌读取权限；通过公开阵容预测并选择后手。</p></div>`;
  modal
    .querySelector(".help-body")
    ?.insertAdjacentHTML(
      "beforeend",
      "<p><b>激战升温：</b>第5次交锋起，每多一次交锋，战斗攻击增加15%、战斗内治疗减少10%（最多减少80%）。不影响战后治疗，不会直接伤害预备席，也不以固定轮数或积分决定胜负。</p>",
    );
  modal.showModal();
}
function showCatalog() {
  modal.innerHTML = `<div class="modal-head"><h2>军团与誓约 · 完整图鉴</h2>${btn("关闭", "close", "text-btn")}</div><div class="catalog-tools">${Object.entries(
    typeName,
  )
    .map(([k, n]) =>
      btn(
        `${n} ${CONTENT[k].length}`,
        "catalog-tab",
        `button small ${tab === k ? "primary" : ""}`,
        `data-id="${k}"`,
      ),
    )
    .join(
      "",
    )}<input id="search" aria-label="搜索图鉴" placeholder="搜索名字、效果或词条" value="${esc(query)}"></div><div id="catalog-list" class="catalog-grid"></div>`;
  if (!modal.open) modal.showModal();
  renderCatalog();
}
function renderCatalog() {
  const q = query.toLowerCase();
  document.querySelector("#catalog-list").innerHTML = CONTENT[tab]
    .filter((x) =>
      (
        JSON.stringify(x) +
        (x.success ? EFFECTS[x.success].text + EFFECTS[x.failure].text : "") +
        (x.tags ? x.tags.map((t) => KEYWORDS[t]).join("") : "")
      )
        .toLowerCase()
        .includes(q),
    )
    .map((x) => itemCard(x.id))
    .join("");
}
function inspect(id) {
  const instance = g?.sides.flatMap((s) => s.units).find((u) => u.uid === id);
  const x = instance ? UNIT_BY_ID[instance.id] : findContent(id);
  if (!x) return;
  modal.innerHTML = `<div class="modal-head"><h2>${x.name}</h2>${btn("关闭", "close", "text-btn")}</div><div class="inspect">${itemCard(x.id)}${x.tags ? `<div><p>${x.flavor}</p><p>人口 ${x.pop} · 生命 ${x.hp} · 攻击 ${x.atk} · 射程 ${x.range} · 攻击间隔 ${x.interval}秒 · 移速 ${x.speed}</p>${(instance ? stats(instance) : x).tags.map((t) => `<p>${KEYWORDS[t]}</p>`).join("")}<p>移动时自动接近最近敌人；嘲讽可改变目标。站定时不主动追击。</p></div>` : ""}</div>`;
  if (!modal.open) modal.showModal();
}
document.addEventListener("click", (e) => {
  const el = e.target.closest("[data-action]");
  if (!el || el.disabled) return;
  e.preventDefault();
  const a = el.dataset.action,
    id = el.dataset.id;
  if (a === "close") {
    modal.close();
    return;
  }
  if (a === "catalog") {
    showCatalog();
    return;
  }
  if (a === "catalog-tab") {
    tab = id;
    showCatalog();
    return;
  }
  if (a === "help") {
    showHelp();
    return;
  }
  if (a === "inspect" || a === "inspect-unit") {
    inspect(id);
    return;
  }
  if (a === "sound") {
    muted = !muted;
    sound();
    render();
    return;
  }
  if (a === "home") {
    if (g?.phase === "battle") {
      toast("请先完成当前18秒战斗再退出。");
      return;
    }
    save();
    g = null;
    render();
    return;
  }
  if (a === "tutorial" || a === "new") {
    start(a === "tutorial");
    return;
  }
  if (a === "continue") {
    try {
      g = JSON.parse(localStorage.getItem(SAVE));
      if (g.version !== 1) throw Error();
      if (g.phase === "battle") g.phase = "reserve";
      render();
    } catch {
      toast("存档无法读取，可以重新开始。");
    }
    return;
  }
  if (!g) return;
  if (a === "tutorial-off") {
    g.tutorial = false;
    save();
    render();
  } else if (a === "bid") bid();
  else if (a === "pick") chooseAuction(id);
  else if (a === "fast-draft") fastDraft();
  else if (a === "select-unit") {
    selectedUnit = id;
    render();
  } else if (a === "slot") place(Number(el.dataset.slot));
  else if (a === "mode") {
    const u = g.deployed[0].find((u) => u.uid === selectedUnit);
    if (u && !g.locked.includes(u.uid))
      u.mode = u.mode === "move" ? "stand" : "move";
    save();
    render();
  } else if (a === "remove") {
    if (!g.locked.includes(selectedUnit))
      g.deployed[0] = g.deployed[0].filter((u) => u.uid !== selectedUnit);
    save();
    render();
  } else if (a === "auto") {
    g.deployed[0] = autoDeploy(
      g.sides[0],
      g.phase === "main" ? 4 : 6,
      g.phase === "reserve"
        ? g.deployed[0].filter((u) => g.locked.includes(u.uid))
        : [],
    );
    save();
    render();
  } else if (a === "lock-main") lockMain();
  else if (a === "card") {
    g.selectedCards[0] = id;
    const val = document.querySelector("#effect-target")?.value;
    save();
    render();
    if (val) document.querySelector("#effect-target").value = val;
  } else if (a === "pledge" || a === "no-pledge") {
    g.selectedPledges[0] =
      a === "pledge" && g.selectedPledges[0] !== id ? id : null;
    const val = document.querySelector("#effect-target")?.value;
    save();
    render();
    if (val) document.querySelector("#effect-target").value = val;
  } else if (a === "lock-card") lockCard();
  else if (a === "nomination") {
    selectedNomination = id;
    render();
  } else if (a === "nominate") nominate();
  else if (a === "contest") contest();
  else if (a === "fight") startFight();
  else if (a === "pause") {
    paused = !paused;
    el.textContent = paused ? "继续" : "暂停";
  } else if (a === "speed") {
    speed = speed === 1 ? 2 : speed === 2 ? 4 : 1;
    el.textContent = "速度 ×" + speed;
  } else if (a === "next") {
    g.round++;
    beginRound();
  }
});
document.addEventListener("input", (e) => {
  if (e.target.id === "search") {
    query = e.target.value;
    renderCatalog();
  }
});
modal.addEventListener("click", (e) => {
  if (e.target === modal) modal.close();
});
window.addEventListener("beforeunload", () => {
  if (g && g.phase !== "battle") save();
});
window.addEventListener("oath-art-ready", drawPreview);
// Read-only diagnostics for reproducible QA. Mutations stay behind normal UI actions.
window.oathDebug = {
  snapshot: () =>
    g
      ? structuredClone({
          ...g,
          botBid: undefined,
          ruleBid: undefined,
          botPlan: undefined,
          selectedCards:
            g.phase === "result" ? g.selectedCards : [g.selectedCards[0], null],
          battle: battle ? { time: battle.time, ended: battle.ended } : null,
        })
      : null,
  counts: () =>
    Object.fromEntries(Object.entries(CONTENT).map(([k, v]) => [k, v.length])),
};
render();
