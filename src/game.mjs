import * as R from "./rules.mjs";
import { SINS, VOICES, BOSS_LINES, LESSONS, roomLayout } from "./content.mjs";
import { moveBody, visible, waypoint, depenetrate } from "./geometry.mjs";
import { fulfilled, frustrated, dominantDesire } from "./desires.mjs";
import * as P from "./progression.mjs";
import { showWorkshop } from "./skill-ui.mjs";
import { Abilities } from "./abilities.mjs";
import { passiveStats } from "./passives.mjs";
import { basicStats } from "./basic.mjs";
import { startShift, tickFarm, recoverResidents } from "./farm.mjs";
import { BossDirector } from "./boss.mjs";
import { Soundscape } from "./audio.mjs";
import { drawBeing, drawMutant } from "./appearance.mjs";
import {keyedAtlas}from'./chroma.mjs';
import {
  desiredProp,
  desiredOpponent,
  desiredPartner,
} from "./human-intent.mjs";
const soundscape = new Soundscape();
let director;
const design = await (await fetch("src/skill-design.json")).json();
const $ = (id) => document.getElementById(id),
  canvas = $("world"),
  ctx = canvas.getContext("2d");
const W = 1600,
  H = 900,
  keys = new Set(),
  mouse = { x: 800, y: 550, down: false };
let running = false,
  paused = false,
  time = 0,
  last = 0,
  stage = 0,
  room = 0,
  seed = Date.now() % 1000000,
  selected = 0,
  tutorial = 0,
  noticeUntil = 0,
  shake = 0,
  wave = 0;
let player,
  guards = [],
  humans = [],
  props = [],
  bullets = [],
  effects = [],
  remnants = [],
  orbit = [],
  mark = null,
  link = null,
  cooldown = 0,
  skillCD = [0, 0],
  dashCD = 0,
  still = 0,
  boss = false,
  bossPhase = 0;
const images = {},
  atlas = {};
let save;
try {
  save = JSON.parse(localStorage.getItem("seven-sins-v1"));
} catch {}
save = Object.assign(
  {
    residents: [],
    currency: 0,
    upgrades: { body: 0, power: 0, capacity: 0 },
    unlocked: 1,
    attempts: 0,
  },
  save || {},
);
P.initProgress(save);
save.settings ??= { muted: false, volume: 0.35, reduceMotion: false };
soundscape.setVolume(save.settings.volume);
soundscape.setMuted(save.settings.muted);
const abilities = new Abilities(design, {
  save,
  get player() {
    return player;
  },
  get mouse() {
    return mouse;
  },
  get orbit() {
    return orbit;
  },
  get link() {
    return link;
  },
  get mark() {
    return mark;
  },
  set mark(v) {
    mark = v;
  },
  guards: () => alive().filter((e) => !e.waiting),
  humans: () =>
    humans.filter((h) => !["rescued", "recovered"].includes(h.state)),
  target: () => enemyTarget(),
  human: () => {
    const h = humanTarget();
    return h && dist(h, mouse) < 100 ? h : null;
  },
  prop: () =>
    props
      .filter((p) => p.type === "temptation")
      .sort((a, b) => dist(a, mouse) - dist(b, mouse))[0],
  move: (a, t, n) => walk(a, t, n, 1),
  hit,
  harmHuman,
  canPlace: (point) =>
    point.x >= 165 &&
    point.x <= 1435 &&
    point.y >= 430 &&
    point.y <= 785 &&
    visible(
      player,
      point,
      props.filter((p) => p.type === "cover"),
    ),
  effect,
  color: (id) => SINS.find((s) => s.id === id).color,
  satisfy: (id) =>
    R.satisfyPlayer(player, id, 8 * (1 + passiveStats(save, id).reliefBonus)),
  prideResult: (n) => desireEvent("pride", { kind: "displace", distance: n }),
  cover: (point, life, hp) => {
    const wall = {
      x: R.clamp(point.x, 180, 1420),
      y: R.clamp(point.y, 445, 770),
      index: 3,
      type: "cover",
      active: true,
      life,
      hp,
    };
    props.push(wall);
    for (const body of [player, ...guards, ...humans])
      depenetrate(
        body,
        props.filter((p) => p.type === "cover"),
      );
  },
  projectiles: (point, count, damage, id, spread, pierce = 0, traits = {}) => {
    const angle = Math.atan2(point.y - player.y, point.x - player.x);
    for (let j = 0; j < count; j++) {
      const a =
        angle + ((j - (count - 1) / 2) * spread) / Math.max(1, count - 1);
      bullets.push({
        x: player.x,
        y: player.y - 35,
        vx: Math.cos(a) * 470,
        vy: Math.sin(a) * 470,
        life: 2,
        friendly: true,
        sin: id,
        source: "skill",
        damage,
        pierce,
        hitIds: [],
        ...traits,
      });
    }
  },
});
const persist = () =>
  localStorage.setItem("seven-sins-v1", JSON.stringify(save));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y),
  alive = () => guards.filter((e) => e.hp > 0),
  sin = () => SINS[selected].id;
function desireEvent(id, event) {
  const stats = passiveStats(save, id),
    code = P.CODES[id],
    rank = (i) => P.passiveRank(save, code + i);
  if (fulfilled(id, event)) {
    R.satisfyPlayer(player, id, 8 * (1 + stats.reliefBonus));
    if (id === "gluttony" && rank("11") && abilities.proc(player, "G11", 6))
      abilities.buff(
        player,
        "protected",
        rank("11") + 1,
        0.05 + 0.05 * rank("11"),
      );
    if (id === "wrath" && rank("15") && abilities.proc(player, "W15", 6))
      abilities.buff(
        player,
        "protected",
        0.5 + 0.5 * rank("15"),
        0.1 + 0.05 * rank("15"),
      );
    if (id === "greed" && rank("12") && abilities.proc(player, "A12", 6))
      abilities.buff(
        player,
        "dashRecovery",
        rank("12") + 1,
        0.03 + 0.07 * rank("12"),
      );
    if (id === "pride" && rank("15"))
      abilities.buff(player, "nextDashRecovery", 3, 0.05 + 0.1 * rank("15"));
  } else if (frustrated(id, event)) {
    R.frustratePlayer(player, id, 5 * (1 - stats.frustrationReduction));
    if (id === "lust" && rank("14") && abilities.proc(player, "L14", 8))
      abilities.buff(
        player,
        "protected",
        0.5 + 0.5 * rank("14"),
        0.1 + 0.05 * rank("14"),
      );
    if (id === "sloth" && rank("14") && abilities.proc(player, "S14", 8))
      abilities.buff(
        player,
        "nextDashDistance",
        1.5 + 0.5 * rank("14"),
        0.05 + 0.05 * rank("14"),
      );
  }
}
function hurtPlayer(amount, source) {
  const kind = source.attackKind || "projectile",
    stats = passiveStats(save, sin(), {
      chasing: player.chasing,
      lowHP: player.hp < player.maxHp * 0.35,
      orbit: orbit.length,
      sideHit: Math.abs(source.x - player.x) > Math.abs(source.y - player.y),
      frontHit: !!player.flip === source.x < player.x,
      surrounded: alive().filter((e) => dist(e, player) < 180).length >= 2,
      copied: player.copied && kind === (player.copiedKind || "projectile"),
      linkNear: link && dist(link, player) < 120,
      stationary: still >= 0.8,
    });
  const adapted =
    player.adaptedKind === kind ? abilities.value(player, "adapted") : 0;
  let damage =
    amount *
    (1 -
      Math.min(
        0.75,
        stats.damageReduction + adapted + abilities.value(player, "protected")+(Math.abs(source.x-player.x)>Math.abs(source.y-player.y)?abilities.value(player,'sideProtected'):0),
      ));
  const shield = player.buffs?.shield;
  if (shield) {
    const absorbed = Math.min(shield.value, damage);
    shield.value -= absorbed;
    damage -= absorbed;
  }
  player.hp -= damage;
  if (damage > 0) {
    const rank = P.passiveRank(save, "E14");
    if (rank && abilities.proc(player, "E14", 8)) {
      player.adaptedKind = kind;
      abilities.buff(player, "adapted", rank + 1, 0.05 + 0.05 * rank);
    }
    abilities.buff(
      player,
      "staggered",
      0.18 *
        (1 -
          Math.min(
            0.7,
            stats.staggerReduction + abilities.value(player, "staggerResist"),
          )),
    );
  }
}
function toast(s) {
  $("toast").textContent = s;
  noticeUntil = time + 4;
  $("toast").style.opacity = 1;
}
function effect(x, y, color, r = 40) {
  const match = SINS.findIndex((s) => s.color === color);
  effects.push({
    x,
    y,
    color,
    r,
    life: 0.45,
    total: 0.45,
    frame: r <= 25 || match < 0 ? 7 : match,
  });
}
let lastSound = -1;
function sound(freq = 100, duration = 0.1, type = "sine", volume = 0.06) {
  if (time - lastSound < 0.045) return;
  lastSound = time;
  soundscape.effect(freq, duration, type, volume);
}
async function loadImage(name, path) {
  const i = new Image();
  i.src = path.replace("assets/", "assets/web/").replace(".png", ".webp");
  try {
    await i.decode();
  } catch {
    i.src = path;
    await i.decode();
  }
  images[name] = i;
  return i;
}
// Chroma-key rendering preparation. Original generated textures remain intact on disk.
function makeAtlas(name) {
  atlas[name] = keyedAtlas(images[name]);
}
await Promise.all([
  loadImage("chamber", "assets/chamber.png"),
  loadImage("actors", "assets/actors-key.png"),
  loadImage("stations", "assets/stations-key.png"),
  loadImage("fx", "assets/combat-fx.png"),
  loadImage("boss", "assets/boss.png"),
  loadImage("people", "assets/people.png"),
  ...['gluttony','wrath','greed','pride','envy','lust'].map(id=>loadImage('mutation-'+id,`assets/mutation-${id}.png`)),
  ...SINS.slice(1).map((s) => loadImage(s.id, `assets/room-${s.id}.png`)),
]);
makeAtlas("actors");
makeAtlas("stations");
makeAtlas("fx");
makeAtlas("boss");
makeAtlas("people");
for(const id of ['gluttony','wrath','greed','pride','envy','lust'])makeAtlas('mutation-'+id);
function sprite(name, index, x, y, height, flip = false, alpha = 1) {
  const a = atlas[name];
  let cw = a.width / 4,
    ch = a.height / 2,
    sx = (index % 4) * cw,
    sy = Math.floor(index / 4) * ch;
  if (name === "boss") {
    const rects = [
        [0, 0.205],
        [0.19, 0.41],
        [0.59, 0.18],
        [0.83, 0.17],
      ],
      r = rects[index];
    sx = r[0] * a.width;
    cw = r[1] * a.width;
    sy = 0;
    ch = a.height;
  }
  const w = (height * cw) / ch;
  ctx.save();
  ctx.globalAlpha = alpha;
  ctx.translate(x, y + (name === "actors" ? height * 0.06 : 0));
  if (flip) ctx.scale(-1, 1);
  ctx.drawImage(a, sx, sy, cw, ch, -w / 2, -height, w, height);
  ctx.restore();
}
loadImage("base", "assets/base.png").catch(() => {});
function shadow(x, y, r = 22) {
  ctx.save();
  ctx.translate(x, y);
  ctx.scale(1, 0.28);
  const g = ctx.createRadialGradient(0, 0, 1, 0, 0, r);
  g.addColorStop(0, "#0009");
  g.addColorStop(1, "#0000");
  ctx.fillStyle = g;
  ctx.fillRect(-r, -r, r * 2, r * 2);
  ctx.restore();
}
function walk(a, target, speed, dt) {
  a.flip = target.x < a.x;
  return moveBody(
    a,
    target,
    speed *
      dt *
      (1 - abilities.value(a, "slow")) *
      (1 + abilities.value(a, "speed")),
    props.filter((p) => p.type === "cover"),
  );
}
function seek(a, target, speed, dt) {
  if (!a.navTime || a.navTime < time) {
    a.navPoint = waypoint(
      a,
      target,
      props.filter((p) => p.type === "cover"),
    );
    a.navTime = time + 0.18;
  }
  return walk(a, a.navPoint || target, speed, dt);
}
function harmHuman(h, damage) {
  if (!h || ["rescued", "recovered"].includes(h.state)) return;
  h.hp -= damage;
  if (!h.flash) {
    h.flash = 0.15;
    effect(h.x, h.y, "#d0c7ba", 30);
  }
  if (h.hp <= 0) {
    h.state = "recovered";
    h.removal = "killed";
    recordRemoval(h, "killed");
    effect(h.x, h.y, "#d0c7ba", 90);
    toast("这个人死了。没有断联，也没有到达基地。");
  }
}
function recordRemoval(h, kind) {
  if (h.removalRecorded) return;
  h.removalRecorded = true;
  remnants.push({ ...h, kind, life: 1.2, total: 1.2 });
}
function hit(e, damage, source = "basic", which = sin()) {
  if (e.hp <= 0 || e.waiting) return;
  e.hp -= damage * (1 + abilities.value(e, "vulnerable"));
  e.flash = 0.1;
  effect(e.x, e.y - 35, SINS.find((s) => s.id === which)?.color || "#eee", 20);
  sound(110, 0.09, "triangle");
  if (e.hp <= 0) {
    if (source !== "human") R.killReward(player, which, source);
    if (source === "basic" && which === "gluttony")
      player.residue = Math.min(4, (player.residue || 0) + 1);
    effect(e.x, e.y, "#d5dfdc", 55);
    shake = 4;
    if (e.id === "boss") toast("回收中枢失去响应。");
  }
}
function humanTarget() {
  return humans
    .filter((h) => !["rescued", "recovered"].includes(h.state))
    .sort((a, b) => dist(a, mouse) - dist(b, mouse))[0];
}
function enemyTarget() {
  return alive()
    .filter((e) => !e.waiting)
    .sort((a, b) => dist(a, mouse) - dist(b, mouse))[0];
}
function spawnRoom() {
  soundscape.room(stage);
  const layout = roomLayout(stage, room, seed);
  boss = stage === 7;
  guards = [];
  humans = [];
  props = [];
  bullets = [];
  effects = [];
  remnants = [];
  mark = null;
  link = null;
  player.x = 800;
  player.y = 735;
  player.immune = 1;
  cooldown = 0;
  wave = 0;
  abilities.fields = [];
  abilities.pending = [];
  if (boss) {
    guards.push({
      id: "boss",
      x: 800,
      y: 535,
      hp: 1800,
      maxHp: 1800,
      cd: 2,
      heavy: true,
      flip: false,
    });
    director = new BossDirector();
    bossPhase = 0;
    toast(BOSS_LINES[0]);
  } else {
    for (let i = 0; i < layout.guards; i++) {
      guards.push({
        id: "g" + i,
        x: 230 + ((i * 191) % 1130),
        y: 450 + ((i * 71) % 170),
        hp: 30 + stage * 6,
        maxHp: 30 + stage * 6,
        cd: 2 + i * 0.18,
        heavy: i % 7 === 6,
        flip: false,
        waiting: stage === 0 && room === 0 && i >= 4,
      });
    }
    for (let i = 0; i < layout.humans; i++) {
      const h = R.createHuman(`${save.attempts}-${stage}-${room}-${i}`);
      Object.assign(h, { x: 330 + i * 360, y: 445, flip: false, decision: 0 });
      humans.push(h);
      props.push({
        x: 330 + i * 360,
        y: 485,
        index: stage === 2 ? 1 : 0,
        active: true,
        type: "temptation",
      });
    }
    layout.cover.forEach((p) =>
      props.push({ ...p, index: 3, type: "cover", active: true }),
    );
    humans.forEach((h) => {
      h.x += 80;
      h.y = 520;
    });
    props.forEach((p, i) => (p.id = `prop-${stage}-${room}-${i}`));
    guards.forEach(
      (e, i) =>
        (e.role = e.heavy
          ? "heavy"
          : stage > 0 && i % 4 === 1
            ? "interceptor"
            : stage >= 2 && i % 6 === 3
              ? "collector"
              : "scout"),
    );
    if (stage === 0 && room === 0)
      guards.forEach((e, i) => {
        const group = Math.floor(i / 4),
          j = i % 4;
        e.x = 360 + group * 420 + (j % 2) * 42;
        e.y = 515 + Math.floor(j / 2) * 42;
        e.training = true;
        e.cd = 4;
      });
    const cover = props.filter((p) => p.type === "cover");
    for (const body of [...guards, ...humans, player]) depenetrate(body, cover);
  }
  updateHUD();
}
function begin() {
  save.attempts++;
  persist();
  stage = 0;
  room = 0;
  selected = 0;
  tutorial = 0;
  orbit = [];
  abilities.reset();
  player = Object.assign(R.createPlayer(), {
    x: 800,
    y: 735,
    immune: 0,
    flip: false,
  });
  player.maxHp = 100 + save.upgrades.body * 15;
  player.hp = player.maxHp;
  running = true;
  paused = false;
  $("overlay").hidden = true;
  spawnRoom();
  toast("WASD 移动。把鼠标指向机器人，靠近后按住左键。");
}
function nextRoom() {
  if (alive().length) {
    toast("回收守卫仍在运行。");
    return;
  }
  if (boss) {
    running = false;
    showEnd();
    return;
  }
  recoverResidents(save);
  persist();
  room++;
  let newSin = false;
  if (room === 5) {
    room = 0;
    stage++;
    newSin = stage < 7 && save.unlocked < stage + 1;
    save.unlocked = Math.max(save.unlocked, Math.min(7, stage + 1));
    persist();
    selected = Math.min(stage, 6);
  }
  player.hp = Math.min(player.maxHp, player.hp + 18);
  spawnRoom();
  if (newSin) showUnlock();
}
function showUnlock() {
  paused = true;
  $("overlay").hidden = false;
  $("overlay").innerHTML =
    `<div class="panel"><span class="eyebrow">DESIRE INTERFACE ${stage + 1} / 7</span><h2>${SINS[stage].name}</h2><p>${LESSONS[stage][0]}</p><p>${LESSONS[stage][1]}</p><p class="muted">旧能力仍然可以使用。数字键切换欲望，Q / E 释放当前装备的技能。解锁与升级不会随死亡消失。</p><button class="primary" id="continue-unlock">接入${SINS[stage].name}</button></div>`;
  $("continue-unlock").onclick = () => {
    paused = false;
    $("overlay").hidden = true;
  };
}
function shoot(e, target, speed = 230) {
  if (e.hp > 0) abilities.enemyAction(e);
  const d = Math.max(1, dist(e, target));
  bullets.push({
    x: e.x,
    y: e.y - 35,
    vx: ((target.x - e.x) / d) * speed,
    vy: ((target.y - e.y) / d) * speed,
    life: 5,
    owner: e.id,
    damage: (e.training ? 3 : 8) * (1 - abilities.value(e, "weakened")),
  });
}
function guardAttack(e, target) {
  if (e.role === "interceptor") {
    if (dist(e, target) < 85) {
      if (target === player && player.immune <= 0) {
        hurtPlayer(10, { ...e, attackKind: "melee" });
        const resistance =
          0.1 * P.passiveRank(save, "P11") + abilities.value(player, "anchor");
        walk(
          player,
          {
            x: player.x + (player.x - e.x) * 4,
            y: player.y + (player.y - e.y) * 4,
          },
          40 * Math.max(0.1, 1 - resistance),
          1,
        );
        player.immune = 0.45;
      } else if (target !== player)
        target.hp -= 10 * (1 - abilities.value(target, "protected"));
      effect(e.x, e.y, "#ba6f65", 65);
      abilities.enemyAction(e);
    }
    return;
  }
  shoot(e, target, e.training ? 170 : e.heavy ? 165 : 210);
  if (e.role === "collector") bullets.at(-1).steal = true;
  if (e.heavy) {
    const source = bullets.at(-1),
      a = Math.atan2(source.vy, source.vx);
    for (const offset of [-0.18, 0.18])
      bullets.push({
        ...source,
        vx: Math.cos(a + offset) * 165,
        vy: Math.sin(a + offset) * 165,
      });
  }
}
function slothAction(e) {
  const b = basicStats(design, save, "sloth", player.sins.sloth);
  if (
    sin() !== "sloth" ||
    still < b.interval ||
    dist(e, player) > b.range ||
    (e.slothNext || 0) > time
  )
    return;
  e.slothNext = time + 0.8;
  hit(
    e,
    b.damage *
      (1 + save.upgrades.power * 0.12) *
      (abilities.value(player, "fieldPower") || 1),
    "basic",
    "sloth",
  );
  const rank = P.passiveRank(save, "S07");
  if (
    rank &&
    abilities.value(player, "fieldPower") &&
    abilities.proc(e, "S07", 1.2)
  )
    abilities.after(0.2, () =>
      hit(e, b.damage * (0.15 + 0.15 * rank), "skill", "sloth"),
    );
}
function attack() {
  if (cooldown > 0 || !running || player.recovery > 0) return;
  for (const h of humans) h.awareUntil = time + 8;
  const id = sin(),
    value = player.sins[id],
    basic = basicStats(design, save, id, value),
    power = 1 + save.upgrades.power * 0.12,
    t = enemyTarget();
  if (keys.has("shift") && !["greed", "lust", "sloth"].includes(id)) {
    const h = humanTarget();
    if (h && dist(h, mouse) < 100 && dist(h, player) < basic.range) {
      cooldown = basic.interval;
      harmHuman(h, basic.damage * power);
      return;
    }
  }
  if (id === "greed") {
    cooldown = 0.15;
    let count = 0;
    const aim = Math.atan2(mouse.y - player.y, mouse.x - player.x),
      half = ((60 + basic.stage * 10) * Math.PI) / 360;
    const captured = bullets.filter((b) => {
      const a = Math.atan2(b.y - (player.y - 35), b.x - player.x) - aim;
      return (
        !b.friendly &&
        b.life > 0 &&
        dist(b, { x: player.x, y: player.y - 35 }) < 170 &&
        Math.abs(Math.atan2(Math.sin(a), Math.cos(a))) <= half &&
        orbit.length < 8
      );
    });
    for (const b of captured) {
      if (orbit.length >= 8) break;
      orbit.push({ phase: Math.random() * 6.28 });
      b.life = 0;
      count++;
    }
    if (count) desireEvent(id, { kind: "acquire", amount: count });
    return;
  }
  if (id === "lust") {
    cooldown = 0.35;
    const target = humanTarget(),
      next = target && dist(target, mouse) < 60 ? target : t;
    if (next && dist(next, player) < 600) {
      if (next !== link) {player.bondTime = 0;const shield=abilities.value(player,'nextLinkShield');if(shield){abilities.buff(player,'shield',3,shield);delete player.buffs.nextLinkShield;}}
      link = next;
      sound(360, 0.1);
    }
    return;
  }
  if (id === "sloth") {
    cooldown = 0.3;
    return;
  }
  if (!t) return;
  const range = basic.range;
  if (id === "envy" && player.copied) {
    cooldown = Math.max(0.6, basic.interval);
    shoot({ x: player.x, y: player.y, id: "player" }, t, 500);
    bullets.at(-1).friendly = true;
    bullets.at(-1).sin = id;
    bullets.at(-1).damage = basic.damage;
    return;
  }
  if (
    dist(t, player) > range ||
    !visible(
      player,
      t,
      props.filter((p) => p.type === "cover"),
    )
  )
    return;
  cooldown = basic.interval;
  if (id === "gluttony") {
    let consumed = 0;
    for (const e of alive())
      if (
        !e.waiting &&
        dist(e, player) < range &&
        visible(
          player,
          e,
          props.filter((p) => p.type === "cover"),
        )
      ) {
        hit(e, basic.damage * power);
        if (e.hp <= 0) consumed++;
      }
    for (const h of humans)
      if (
        !["rescued", "recovered"].includes(h.state) &&
        dist(h, player) < range &&
        visible(
          player,
          h,
          props.filter((p) => p.type === "cover"),
        )
      )
        harmHuman(h, basic.damage * power * 0.5);
    if (consumed) {
      const heal = player.maxHp * (0.03 + 0.01 * basic.stage),
        overflow = Math.max(0, player.hp + heal - player.maxHp);
      player.hp = Math.min(player.maxHp, player.hp + heal);
      const rank = P.passiveRank(save, "G13");
      if (rank && overflow)
        abilities.buff(
          player,
          "shield",
          3 + rank,
          Math.min(overflow, player.maxHp * (0.01 + 0.03 * rank)),
        );
      desireEvent(id, { kind: "consume", amount: consumed });
    } else desireEvent(id, { kind: "meal-denied" });
    shake = 5;
    effect(player.x, player.y, "#c2ad79", range);
  }
  if (id === "wrath") {
    const same = mark === t;
    mark = t;
    hit(t, basic.damage * power * (same ? 1.1 + 0.05 * basic.stage : 1));
    if (same)
      desireEvent(id, {
        kind: "revenge",
        target: t.id,
        mark: mark.id,
        damage: basic.damage,
      });
  }
  if (id === "pride") {
    const old = { x: t.x, y: t.y };
    if (!t.heavy) {
      walk(
        t,
        { x: t.x + (t.x - player.x) * 2, y: t.y + (t.y - player.y) * 2 },
        900 * (1 + 0.12 * basic.stage),
        0.12,
      );
    }
    hit(t, basic.damage * power);
    desireEvent(id, { kind: "displace", distance: dist(old, t) });
  }
  if (id === "envy") {
    hit(t, basic.damage * power);
    if (t.heavy || abilities.value(t, "sealed")) {
      desireEvent(id, { kind: "copy-denied" });
      toast("装甲封住了模块，无法直接复制。");
    } else {
      const fresh = !player.copied;
      player.copied = true;
      desireEvent(id, { kind: "copy", newAbility: fresh });
      toast("已夺取射击模块：下一次普攻发射复制弹。");
    }
  }
}
function cast(slot) {
  const error = abilities.cast(sin(), slot);
  if (error) toast(error);
  else {
    sound(70, 0.25, "triangle", 0.04);
    shake = 4;
  }
}
function lineDistance(p, a, b) {
  const dx = b.x - a.x,
    dy = b.y - a.y,
    t = R.clamp(
      ((p.x - a.x) * dx + (p.y - a.y) * dy) / (dx * dx + dy * dy || 1),
      0,
      1,
    );
  return Math.hypot(p.x - a.x - dx * t, p.y - a.y - dy * t);
}
function inject() {
  if (player.recovery > 0) return;
  const h = humanTarget(),
    stats = passiveStats(save, sin());
  if (!h || dist(h, mouse) > 100 || dist(h, player) > 240 * stats.injectRange) {
    toast("靠近白衣人，把鼠标指向他，再按右键。");
    return;
  }
  const n = R.inject(player, h, sin(), 20);
  if (!n) {
    toast("罪槽不足。先用普攻击败守卫。");
    return;
  }
  player.recovery = 0.3 * (sin()==='lust'&&link!==h?1:stats.injectDuration);
  if (stats.protection && abilities.proc(h, P.CODES[sin()] + "18", 8))
    abilities.buff(h, "protected", stats.protectionTime, stats.protection);
  effect(h.x, h.y, SINS[selected].color, 55);
  sound(210, 0.25);
  h.chosen = sin();
  if (tutorial < 2) tutorial = 2;
  toast(
    `已注入${n}点${SINS[selected].name}。40点开始断联计时；满足欲望会重新计时。`,
  );
}
function interact() {
  if (player.y < 485 && Math.abs(player.x - 800) < 90) {
    nextRoom();
    return;
  }
  const p = props
    .filter((p) => p.type === "temptation")
    .sort((a, b) => dist(a, player) - dist(b, player))[0];
  if (p && dist(p, player) < 110) {
    p.active = !p.active;
    effect(p.x, p.y, "#ddd", 40);
    toast(
      p.active
        ? "供应装置已开启：附近的人可能得到满足。"
        : "供应装置已关闭。其他开启的装置仍会吸引他。",
    );
    return;
  }
  toast("靠近供应装置可开关；清场后前往后方中央门。");
}
function rescue(h) {
  const ledger = new Set(save.residents.map((r) => r.id)),
    id = h.chosen || "gluttony",
    stats = passiveStats(save, id);
  if (!R.rescueReturn(player, h, ledger, 0.05 + stats.rescueBonus)) return;
  recordRemoval(h, "rescued");
  const rank = P.passiveRank(save, P.CODES[id] + "20");
  if (rank) {
    if (["gluttony", "greed"].includes(id))
      abilities.buff(
        player,
        "shield",
        rank === 3 ? 4 : 3,
        player.maxHp * (0.01 + 0.03 * rank),
      );
    else if (id === "wrath")
      abilities.buff(player, "speed", 1 + rank, 0.05 + 0.05 * rank);
    else if (id === "pride")abilities.buff(player,"sideProtected",1+rank,.05+.05*rank);
    else if (id === "sloth")abilities.buff(player,"nextRestProtection",5,rank);
    else if (id === "lust")abilities.buff(player,"nextLinkShield",5,player.maxHp*(.01+.03*rank));
    else abilities.buff(player, "nextCopyRecovery", 5, 0.05 + 0.05 * rank);
  }
  save.residents.push({
    id: h.id,
    sin: id,
    mode: "rest",
    strain: 0,
    voice: VOICES[save.residents.length % VOICES.length],
  });
  persist();
  effect(h.x, h.y, "#b4dfc9", 100);
  toast("连接断开。已抵达基地，之后即使失败也不会失去他。");
  tutorial = 3;
}
function tick(dt) {
  time += dt;
  if (time > noticeUntil) $("toast").style.opacity = 0;
  if ((running && !paused) || $("residents")) {
    if (tickFarm(save, dt)) {
      persist();
      if ($("residents")) showBase();
      else toast("基地的一班生产结束了。材料已保存。");
    }
    if ($("produce") && save.shift?.remaining > 0) {
      $("produce").disabled = true;
      $("produce").textContent =
        `本班剩余 ${Math.ceil(save.shift.remaining)} 秒`;
    }
  }
  if (!running || paused) return;
  cooldown = Math.max(0, cooldown - dt);
  skillCD = skillCD.map((x) => Math.max(0, x - dt));
  dashCD = Math.max(0, dashCD - dt);
  player.immune = Math.max(0, player.immune - dt);
  abilities.tick(dt);
  for (const p of props) if (p.life !== undefined) p.life -= dt;
  props = props.filter(
    (p) =>
      (p.life === undefined || p.life > 0) && (p.hp === undefined || p.hp > 0),
  );
  for (const h of humans) {
    if (h.hp <= 0 && h.state === "desiring") {
      h.state = "recovered";
      h.removal = "system";
      recordRemoval(h, "system");
      effect(h.x, h.y, "#d8ded8", 90);
      toast("异常体已被系统回收。");
    }
    h.flash = Math.max(0, (h.flash || 0) - dt);
  }
  const central = guards.find((e) => e.id === "boss" && e.hp > 0);
  if (boss && central) {
    const events = director.tick(dt, central, player);
    if (events.some((e) => e.type === "bullet" || e.type === "pulse")) {
      abilities.enemyAction(central);
      slothAction(central);
    }
    for (const event of events) {
      if (event.type === "bullet")
        bullets.push({
          x: event.x,
          y: event.y - 35,
          vx: Math.cos(event.angle) * event.speed,
          vy: Math.sin(event.angle) * event.speed,
          life: 6,
          owner: "boss",
          damage: 12,
        });
      if (event.type === "pulse") {
        effect(event.x, event.y, "#bd8ba6", event.radius);
        if (dist(player, event) < event.radius && player.immune <= 0) {
          hurtPlayer(18, event);
          player.immune = 0.5;
        }
      }
      if (event.type === "adds" && alive().length < 9)
        for (let i = 0; i < event.count; i++)
          guards.push({
            id: "add-" + time + "-" + i,
            x: 300 + i * 320,
            y: 460,
            hp: 45,
            maxHp: 45,
            cd: 3 + i * 0.2,
            heavy: false,
          });
      if (event.type === "phase") toast(BOSS_LINES[event.phase + 1]);
    }
  }
  let dx =
      (keys.has("d") || keys.has("arrowright") ? 1 : 0) -
      (keys.has("a") || keys.has("arrowleft") ? 1 : 0),
    dy =
      (keys.has("s") || keys.has("arrowdown") ? 1 : 0) -
      (keys.has("w") || keys.has("arrowup") ? 1 : 0);
  const moving = dx || dy;
  player.moving = !!moving;
  player.chasing = !!(
    moving &&
    mark?.hp > 0 &&
    dx * (mark.x - player.x) + dy * (mark.y - player.y) > 0
  );
  if (moving) {
    const len = Math.hypot(dx, dy),
      chase =
        sin() === "wrath" && player.chasing
          ? 1 + 0.04 * R.basicStage(player.sins.wrath)
          : 1;
    walk(
      player,
      { x: player.x + (dx / len) * 100, y: player.y + (dy / len) * 100 },
      210 * chase * (abilities.value(player, "staggered") ? 0.45 : 1),
      dt,
    );
    still = 0;
    player.restPaid = false;
  } else {
    still += dt;
    if(sin()==='sloth'&&still>=basicStats(design,save,'sloth',player.sins.sloth).interval&&abilities.value(player,'nextRestProtection')){const rank=abilities.value(player,'nextRestProtection');abilities.buff(player,'protected',rank+1,.05+.05*rank);delete player.buffs.nextRestProtection;}
    if (still >= 3 && !player.restPaid) {
      desireEvent("sloth", { kind: "rest", duration: still });
      player.restPaid = true;
    }
  }
  if (mouse.down) attack();
  if (
    stage === 0 &&
    room === 0 &&
    !guards.some((e) => e.hp > 0 && !e.waiting) &&
    guards.some((e) => e.waiting)
  ) {
    wave++;
    guards
      .filter((e) => e.waiting)
      .slice(0, 4)
      .forEach((e) => {
        e.waiting = false;
        e.cd = 3;
      });
    toast("下一组回收守卫已启动。普攻击败可继续积累暴食。");
  }
  for (const e of alive()) {
    if (e.waiting || e.id === "boss") continue;
    e.flash = Math.max(0, (e.flash || 0) - dt);
    if (e.stun > 0) {
      e.stun -= dt;
      continue;
    }
    const candidates = humans.filter(
      (h) => h.state === "desiring" && dist(h, e) < 260,
    );
    const target =
      candidates.sort((a, b) => dist(e, a) - dist(e, b))[0] || player;
    e.cd -= dt;
    if (dist(e, target) > (e.role === "interceptor" ? 60 : 210)) {
      e.travel =
        (e.travel || 0) +
        seek(e, target, e.role === "interceptor" ? 95 : 45 + stage * 4, dt);
      if (e.travel >= 60) {
        e.travel %= 60;
        slothAction(e);
      }
    }
    if (e.cd < 0) {
      e.cd = e.training ? 3.5 : 2.6;
      guardAttack(e, target);
      slothAction(e);
    }
  }
  for (const h of humans) {
    if (h.state !== "desiring") continue;
    const id = dominantDesire(h.sins),
      value = h.sins[id],
      satisfied = new Set();
    h.chosen = id;
    h.decision -= dt;
    const targets = alive().filter((e) => !e.waiting),
      nearest = targets.sort((a, b) => dist(h, a) - dist(h, b))[0];
    if (id === "gluttony") {
      const target = desiredProp(h, props, 0);
      if (target) {
        seek(h, target, 20 + value * 0.6, dt);
        if (dist(h, target) < 28) satisfied.add(id);
      }
    } else if (id === "greed") {
      const bullet = bullets.find(
        (b) => !b.friendly && b.life > 0 && dist(h, b) < 80,
      );
      if (bullet) {
        bullet.life = 0;
        h.hoard = (h.hoard || 0) + 1;
        satisfied.add(id);
      }
      const item = desiredProp(h, props, 1);
      if (item) {
        seek(h, item, 20 + value * 0.6, dt);
        if (dist(h, item) < 28) {
          item.active = false;
          h.hoard = (h.hoard || 0) + 1;
          satisfied.add(id);
        }
      }
      if (nearest && dist(h, nearest) < 95 && h.hoard && h.decision < 0) {
        hit(nearest, 12 + value * 0.2, "human", id);
        h.decision = 1;
      }
    } else if (id === "lust") {
      const partner = desiredPartner(h, humans, player);
      seek(h, partner, 40 + value * 0.4, dt);
      h.bondTime = dist(h, partner) < 90 ? (h.bondTime || 0) + dt : 0;
      if (
        fulfilled(id, {
          kind: "bond",
          duration: h.bondTime,
          distance: dist(h, partner),
        })
      )
        satisfied.add(id);
      if (nearest && lineDistance(nearest, h, partner) < 25)
        hit(nearest, dt * (10 + value * 0.25), "human", id);
    } else if (id === "sloth") {
      const travelling = h.restSpot && dist(h, h.restSpot) > 25;
      if (travelling) seek(h, h.restSpot, 35 + value * 0.3, dt);
      const disturbed =
        travelling ||
        abilities.value(h, "disturbed") > 0 ||
        targets.some((e) => dist(e, h) < 150) ||
        dist(player, h) < 80;
      h.restTime = disturbed ? 0 : (h.restTime || 0) + dt;
      if (fulfilled(id, { kind: "rest", duration: h.restTime }))
        satisfied.add(id);
      if (disturbed && nearest && dist(nearest, h) < 150 && h.decision < 0) {
        hit(nearest, 10 + value * 0.2, "human", id);
        h.decision = 2;
      }
    } else {
      const e = desiredOpponent(h, targets, id);
      if (e) {
        seek(h, e, 30 + value * 0.65, dt);
        if (dist(h, e) < 65 && h.decision < 0) {
          h.decision = 1;
          let success = false;
          if (id === "pride") {
            const displacement = e.heavy
              ? 0
              : walk(
                  e,
                  { x: e.x + (e.x - h.x) * 3, y: e.y + (e.y - h.y) * 3 },
                  900,
                  0.12,
                );
            success = fulfilled(id, {
              kind: "displace",
              distance: displacement,
            });
          } else if (id === "envy") {
            success =
              !h.copiedModule && !e.heavy && !abilities.value(e, "sealed");
            if (success) h.copiedModule = true;
          } else success = true;
          hit(e, 8 + value * 0.15, "human", id);
          if (success) satisfied.add(id);
        }
      }
    }
    if (R.advanceHuman(h, dt, satisfied)) rescue(h);
  }
  for (const b of bullets) {
    const lineRank = P.passiveRank(save, "L09");
    if (
      !b.lineSlowed &&
      lineRank &&
      link &&
      abilities.value(player, "lineSlow") &&
      lineDistance(b, player, link) < 25
    ) {
      b.lineSlowed = true;
      b.slowLeft = 0.2 + 0.2 * lineRank;
      b.slowFactor = 0.1 + 0.1 * lineRank;
    }
    b.slowLeft = Math.max(0, (b.slowLeft || 0) - dt);
    const pace = b.slowLeft > 0 ? 1 - b.slowFactor : 1;
    b.x += b.vx * dt * pace;
    b.y += b.vy * dt * pace;
    b.life -= dt;
    if (b.friendly) {
      for (const e of alive())
        if (
          !e.waiting &&
          dist(b, { x: e.x, y: e.y - 35 }) < 28 &&
          !b.hitIds?.includes(e.id)
        ) {
          hit(e, b.damage || 25, b.source || "basic", b.sin);
          if (b.acid) abilities.field(e.x, e.y, 50, 2, b.acid / 2, b.sin);
          if (b.vulnerable) abilities.buff(e, "vulnerable", 3, b.vulnerable);
          b.hitIds ??= [];
          b.hitIds.push(e.id);
          if (b.pierce > 0) b.pierce--;
          else b.life = 0;
          break;
        }
      if (b.life > 0)
        for (const h of humans)
          if (
            !["rescued", "recovered"].includes(h.state) &&
            dist(b, { x: h.x, y: h.y - 35 }) < 24 &&
            !b.hitIds?.includes(h.id)
          ) {
            harmHuman(h, (b.damage || 25) * 0.5);
            b.hitIds ??= [];
            b.hitIds.push(h.id);
            if (b.pierce > 0) b.pierce--;
            else b.life = 0;
            break;
          }
    } else {
      if (
        dist(b, { x: player.x, y: player.y - 35 }) < 24 &&
        player.immune <= 0
      ) {
        if (still >= 1) desireEvent("sloth", { kind: "rest-interrupted" });
        if (b.steal && orbit.length) {
          orbit.pop();
          desireEvent("greed", { kind: "possession-lost" });
        }
        still = 0;
        player.restPaid = false;
        hurtPlayer(b.damage || 8, b);
        player.immune = 0.45;
        b.life = 0;
        shake = 5;
        sound(55, 0.18);
      }
      for (const h of humans)
        if (
          b.life > 0 &&
          h.state === "desiring" &&
          dist(b, { x: h.x, y: h.y - 35 }) < 24
        ) {
          const rank = P.passiveRank(save, "L18"),
            bondProtection = link === h && rank ? 0.03 + 0.07 * rank : 0;
          h.hp -=
            12 *
            (1 -
              Math.min(0.75, abilities.value(h, "protected") + bondProtection));
          b.life = 0;
          if (h.hp <= 0) {
            h.state = "recovered";
            recordRemoval(h, "system");
            toast("异常体被系统回收。未能解救。");
          }
          break;
        }
    }
    for (const p of props)
      if (p.type === "cover" && dist(b, { x: p.x, y: p.y - 35 }) < 42) {
        b.life = 0;
        if (p.hp !== undefined) p.hp -= 8;
      }
  }
  bullets = bullets.filter((b) => b.life > 0);
  const greedBasic = basicStats(design, save, "greed", player.sins.greed);
  for (let i = 0; i < orbit.length; i++) {
    const a = time * 2 + (i * Math.PI * 2) / orbit.length,
      o = { x: player.x + Math.cos(a) * 80, y: player.y + Math.sin(a) * 48 },
      times = (orbit[i].hitTimes ??= {});
    for (const e of alive())
      if (!e.waiting && dist(o, e) < 32 && (times[e.id] || 0) <= time) {
        hit(
          e,
          greedBasic.damage * (1 + save.upgrades.power * 0.12),
          "basic",
          "greed",
        );
        times[e.id] = time + 0.3;
      }
    const protection = P.passiveRank(save, "A18");
    for (const h of humans)
      if (
        !["rescued", "recovered"].includes(h.state) &&
        dist(o, h) < 28 &&
        (times[h.id] || 0) <= time
      ) {
        harmHuman(
          h,
          greedBasic.damage *
            0.5 *
            (protection ? 1 - (0.05 + 0.15 * protection) : 1),
        );
        times[h.id] = time + 0.3;
      }
  }
  const lustBasic = basicStats(design, save, "lust", player.sins.lust);
  if (
    link &&
    link.hp > 0 &&
    dist(player, link) < lustBasic.range &&
    visible(
      player,
      link,
      props.filter((p) => p.type === "cover"),
    )
  ) {
    player.bondTime = (player.bondTime || 0) + dt;
    if (player.bondTime >= 2) {
      desireEvent("lust", {
        kind: "bond",
        duration: player.bondTime,
        distance: dist(player, link),
      });
      player.bondTime = 0;
    }
    for (const e of alive())
      if (
        lineDistance(e, player, link) <
        [7.2, 9.6, 12.6, 16.2, 20.4, 25.2][lustBasic.stage]
      ) {
        hit(
          e,
          dt *
            ((lustBasic.damage / 0.3) * (1 + save.upgrades.power * 0.12)) *
            (e === link ? 0.25 : 1),
          "basic",
          "lust",
        );
        if (abilities.value(player, "lineDamage"))
          hit(
            e,
            dt *
              abilities.value(player, "lineDamage") *
              (e === link ? 0.25 : 1),
            "skill",
            "lust",
          );
        if (abilities.value(player, "lineSlow"))
          abilities.buff(e, "slow", 0.1, abilities.value(player, "lineSlow"));
      }
  } else if (link) {
    if (link.hp > 0 && !["rescued", "recovered"].includes(link.state))
      desireEvent("lust", { kind: "bond-broken" });
    link = null;
  }
  effects.forEach((e) => (e.life -= dt));
  effects = effects.filter((e) => e.life > 0);
  remnants.forEach((e) => (e.life -= dt));
  remnants = remnants.filter((e) => e.life > 0);
  shake = Math.max(0, shake - dt * 25);
  if (player.hp <= 0 || !player.alive) {
    running = false;
    showDeath();
  }
  if (tutorial === 0 && player.sins.gluttony >= 40) tutorial = 1;
  updateHUD();
}
function updateHUD() {
  if (!player) return;
  $("hp").style.width = (100 * player.hp) / player.maxHp + "%";
  $("hpnum").textContent = Math.max(0, Math.ceil(player.hp));
  $("pain").style.width = player.pain + "%";
  $("painnum").textContent = `${Math.ceil(player.pain)} / 100`;
  $("count").textContent = `已解救 ${save.residents.length}`;
  $("location").textContent = boss
    ? "第一大关 / 回收中枢"
    : `第一大关 · ${stage + 1}/7 / ${SINS[stage].room} · ${room + 1}/5`;
  for (let i = 0; i < 7; i++) {
    const b = $("sins").children[i];
    b.classList.toggle("active", selected === i);
    b.disabled = i >= save.unlocked;
    b.querySelector("b").textContent = Math.floor(player.sins[SINS[i].id]);
    b.querySelector("i").style.width = player.sins[SINS[i].id] + "%";
  }
  const intro = [
    [
      "先学会保护自己",
      "WASD 移动，近距离按住左键吞食，空格闪避。白衣人不是守卫：吞食、弹丸和范围技能可能误伤。",
    ],
    [
      "把欲望交还给一个人",
      "普攻击败守卫获得暴食。右键向白衣人注入20点；至少40点才能开始断联。",
    ],
    [
      "别让他得到满足",
      "走到食物装置旁按 F 关闭供应。保护白衣人，头顶圆环完成后即可解救。满足会重新计时。",
    ],
    [
      "找到下一间检测室",
      "清除守卫后，走到后方中央门按 F。未解救的人可以继续等待，没有清场倒计时。",
    ],
  ];
  const list = abilities.active(sin()),
    skills = list
      .map((n, i) => `${["Q", "E", "R", "T", "G"][i]} ${n.name}`)
      .join(" / ");
  const t =
    stage === 0 && room === 0
      ? intro[tutorial]
      : [SINS[selected].basic, skills + "。清场后到后方门按 F。"];
  $("task").textContent = t[0];
  $("explain").textContent = t[1];
  $("target").textContent =
    `普攻 ${cooldown > 0 ? cooldown.toFixed(1) + "秒后就绪" : "就绪"} · 不消耗罪　残渣 ${player.residue || 0} · 捕获弹 ${orbit.length}`;
  const signature = list.map((n) => n.code).join();
  if ($("skillbar").dataset.signature !== signature) {
    $("skillbar").dataset.signature = signature;
    $("skillbar").replaceChildren(
      ...list.map((n, i) => {
        const el = document.createElement("div");
        el.className = "skill-chip";
        const key = document.createElement("kbd");
        key.textContent = ["Q", "E", "R", "T", "G"][i];
        el.append(
          key,
          document.createTextNode(n.name),
          document.createElement("small"),
          document.createElement("i"),
        );
        return el;
      }),
    );
  }
  list.forEach((n, i) => {
    const cd = abilities.cooldowns[n.code] || 0,
      el = $("skillbar").children[i];
    el.querySelector("small").textContent =
      cd > 0 ? `冷却 ${cd.toFixed(1)}秒` : n.cast;
    el.querySelector("i").style.width =
      `${100 * (1 - cd / Number.parseFloat(n.cd))}%`;
  });
}
function draw() {
  const inBase = !$("overlay").hidden && !!$("residents");
  $("game").classList.toggle("base-view", inBase);
  ctx.clearRect(0, 0, W, H);
  if (inBase) {
    ctx.drawImage(images.base || images.chamber, 0, 0, W, H);
    save.residents.slice(0, 8).forEach((r, i) => {
      const x = 440 + (i % 3) * 130,
        y = 630 + Math.floor(i / 3) * 75;
      shadow(x, y, 24);
      drawBeing(
        ctx,
        atlas.people,
        {},
        r.mode === "work" ? 2 : 0,
        x,
        y,
        115,
        time,
        atlas.fx,
        1,
      );
      if (r.mode === "work" && save.shift?.remaining > 0)
        sprite(
          "fx",
          7,
          x,
          y - 90,
          35,
          false,
          0.25 + 0.1 * Math.sin(time * 2 + i),
        );
    });
    return;
  }
  ctx.save();
  if (shake > 0 && !save.settings.reduceMotion)
    ctx.translate(
      Math.sin(time * 91) * shake,
      Math.cos(time * 78) * shake * 0.5,
    );
  ctx.drawImage(
    images[SINS[Math.min(stage, 6)].id] || images.chamber,
    0,
    0,
    W,
    H,
  );
  if (!player) {
    ctx.restore();
    return;
  }
  const entities = [
    ...props.map((p) => ({ ...p, kind: "prop" })),
    ...guards
      .filter((e) => e.hp > 0 && !e.waiting)
      .map((e) => ({ ...e, kind: "guard" })),
    ...humans
      .filter((h) => !["rescued", "recovered"].includes(h.state))
      .map((h) => ({ ...h, kind: "human" })),
    { ...player, kind: "player" },
  ].sort((a, b) => a.y - b.y);
  for (const e of entities) {
    shadow(e.x, e.y, e.kind === "prop" ? 40 : 24);
    if (e.kind === "prop") {
      sprite(
        "stations",
        e.index,
        e.x,
        e.y,
        e.type === "cover" ? 95 : 130,
        false,
        e.active ? 1 : 0.4,
      );
      continue;
    }
    const height = e.kind === "guard" ? (e.id === "boss" ? 310 : 125) : 110;
    const index =
      e.kind === "player" ? (e.moving ? Math.floor(time * 7) % 4 : 0) : 6;
    ctx.save();
    if (e.flash > 0 && !save.settings.reduceMotion)
      ctx.filter = "brightness(2)";
    if (e.kind === "player" && e.immune > 0) ctx.globalAlpha = 0.75;
    if (e.id === "boss") sprite("boss", e.pose || 0, e.x, e.y, height);
    else if (e.kind === "human")
      drawBeing(
        ctx,
        atlas.people,
        e,
        e.state === "desiring" ? 2 : e.awareUntil > time ? 0 : 1,
        e.x,
        e.y,
        120,
        time,
        atlas.fx,
        1,
      );
    else if (e.kind === "player")
      drawMutant(ctx, atlas, e, index, e.x, e.y, height, time);
    else sprite("actors", index, e.x, e.y, height, e.flip);
    ctx.restore();
    if (e.kind === "guard") {
      ctx.fillStyle = "#171b1c";
      ctx.fillRect(e.x - 23, e.y - height - 3, 46, 3);
      ctx.fillStyle = "#b56e65";
      ctx.fillRect(e.x - 23, e.y - height - 3, (46 * e.hp) / e.maxHp, 3);
      if (mark?.id === e.id) {
        ctx.strokeStyle = "#bd6e65";
        ctx.strokeRect(e.x - 28, e.y - height + 10, 56, 60);
      }
    }
    if (e.kind === "human" && e.hp < 100) {
      ctx.fillStyle = "#202523";
      ctx.fillRect(e.x - 20, e.y + 8, 40, 3);
      ctx.fillStyle = "#b5967a";
      ctx.fillRect(e.x - 20, e.y + 8, (40 * Math.max(0, e.hp)) / 100, 3);
    }
    if (e.kind === "human" && e.state === "desiring") {
      const id = e.chosen || "gluttony",
        d = R.rescueDuration(e.sins[id]),
        progress = e.unmet[id] / d;
      ctx.strokeStyle = SINS.find((s) => s.id === id).color;
      ctx.lineWidth = 3;
      ctx.beginPath();
      ctx.arc(
        e.x,
        e.y - height - 10,
        12,
        -Math.PI / 2,
        -Math.PI / 2 + Math.PI * 2 * Math.min(1, progress),
      );
      ctx.stroke();
      ctx.font = "11px sans-serif";
      ctx.fillStyle = "#d5dad2";
      ctx.textAlign = "center";
      ctx.fillText(
        `${Math.floor(e.sins[id])} · ${Number.isFinite(d) ? Math.max(0, Math.ceil(d - e.unmet[id])) + "s" : "需40罪"}`,
        e.x,
        e.y - height - 28,
      );
    }
  }
  for (const e of remnants) {
    const progress = 1 - e.life / e.total;
    ctx.save();
    ctx.globalAlpha = 1 - progress;
    ctx.filter =
      e.kind === "rescued" ? "brightness(1.3)" : "grayscale(1) brightness(.55)";
    drawBeing(
      ctx,
      atlas.people,
      e,
      2,
      e.x,
      e.y + (e.kind === "rescued" ? -40 : 15) * progress,
      120 * (e.kind === "killed" ? 1 - 0.45 * progress : 1),
      time,
      atlas.fx,
      1,
    );
    ctx.restore();
    if (e.kind === "system")
      sprite("fx", 3, e.x, e.y - 20, 150, false, Math.sin(progress * Math.PI));
  }
  for (const b of bullets) {
    ctx.shadowBlur = 12;
    ctx.shadowColor = b.friendly ? "#bddecb" : "#cf8978";
    ctx.fillStyle = b.friendly ? "#d8f1df" : "#e6a591";
    ctx.beginPath();
    ctx.ellipse(b.x, b.y, 4, 3, 0, 0, Math.PI * 2);
    ctx.fill();
  }
  ctx.shadowBlur = 0;
  if (link) {
    ctx.strokeStyle = "#b787a0";
    ctx.lineWidth = 2 + player.sins.lust * 0.04;
    ctx.beginPath();
    ctx.moveTo(player.x, player.y - 40);
    ctx.lineTo(link.x, link.y - 40);
    ctx.stroke();
  }
  orbit.forEach((o, i) => {
    const a = time * 2 + (i * Math.PI * 2) / orbit.length;
    ctx.fillStyle = "#e4cd8f";
    ctx.beginPath();
    ctx.arc(
      player.x + Math.cos(a) * 80,
      player.y - 20 + Math.sin(a) * 48,
      5,
      0,
      7,
    );
    ctx.fill();
  });
  for (const f of abilities.fields) {
    sprite(
      "fx",
      f.actionDamage ? 6 : 3,
      f.x,
      f.y + f.radius * 0.3,
      f.radius * 1.5,
      false,
      Math.min(0.65, f.left / 0.3),
    );
  }
  for (const e of effects) {
    const progress = 1 - e.life / e.total,
      envelope = Math.sin(progress * Math.PI),
      size = Math.max(35, e.r * 1.5) * (0.65 + 0.35 * progress);
    ctx.save();
    ctx.translate(e.x, e.y - 25);
    ctx.scale(1, e.frame === 0 ? 0.25 + 0.75 * envelope : 1);
    sprite("fx", e.frame, 0, size * 0.5, size, false, envelope * 0.85);
    ctx.restore();
  }
  ctx.globalAlpha = 1;
  for (const e of alive())
    if (!e.waiting && e.cd < 0.55) {
      ctx.save();
      ctx.globalAlpha = (0.55 - e.cd) / 0.8;
      ctx.strokeStyle = "#b58d7b";
      ctx.setLineDash([5, 9]);
      ctx.beginPath();
      ctx.moveTo(e.x, e.y);
      ctx.lineTo(player.x, player.y);
      ctx.stroke();
      ctx.restore();
    }
  if (boss && director)
    for (const t of director.telegraphs) {
      ctx.save();
      ctx.strokeStyle = "#d2a897";
      ctx.lineWidth = 3;
      ctx.globalAlpha = 0.4 + 0.4 * Math.sin(time * 15) ** 2;
      ctx.beginPath();
      if (t.kind === 2)
        ctx.ellipse(
          t.x,
          t.y,
          75 + director.phase * 15,
          45 + director.phase * 9,
          0,
          0,
          Math.PI * 2,
        );
      else {
        const b = guards.find((e) => e.id === "boss");
        ctx.moveTo(b.x, b.y);
        ctx.lineTo(b.x + Math.cos(t.aim) * 600, b.y + Math.sin(t.aim) * 600);
      }
      ctx.stroke();
      ctx.restore();
    }
  if (!alive().length) {
    ctx.fillStyle = "#a5c1af";
    ctx.font = "14px Microsoft YaHei";
    ctx.textAlign = "center";
    ctx.fillText(boss ? "F · 离开检测设施" : "F · 下一检测室", 800, 396);
  }
  ctx.restore();
  const vignette = ctx.createRadialGradient(800, 520, 240, 800, 500, 920);
  vignette.addColorStop(0, "#0000");
  vignette.addColorStop(1, "#000a");
  ctx.fillStyle = vignette;
  ctx.fillRect(0, 0, W, H);
}
function showDeath() {
  $("overlay").hidden = false;
  $("overlay").innerHTML =
    `<div class="panel"><span class="eyebrow">CONNECTION LOST</span><h2>连接断开。</h2><p>已经离开的人没有被带回去。<br>能力与升级保留；下次从本大关第一室开始，罪槽清空。</p><button class="primary" id="retry">重新接入</button><button id="camp">返回基地 · ${save.residents.length}人</button></div>`;
  $("retry").onclick = begin;
  $("camp").onclick = showBase;
}
function showEnd() {
  $("overlay").hidden = false;
  $("overlay").innerHTML =
    `<div class="panel"><span class="eyebrow">FIRST DESCENT COMPLETE</span><h2>你带回了欲望。</h2><p>“你要证明的，是他们想活，还是你想让他们这样活？”</p><p>回收中枢停止了。这个问题没有。</p><button class="primary" id="camp">回到基地</button></div>`;
  $("camp").onclick = showBase;
}
function showBase() {
  paused = true;
  $("overlay").hidden = false;
  $("overlay").innerHTML =
    `<div class="panel"><span class="eyebrow">OUTSIDE / 痛苦农场</span><h2>离开之后</h2><p>痛苦材料：<strong>${Math.floor(save.currency)}</strong>。每完成一次生产，工作者产生材料并积累负担；休息降低负担。不能无限连续生产。</p><div id="residents"></div><div class="upgrades" id="upgrades"></div><button id="produce" class="primary">进行一轮生产</button><button id="return">${running ? "返回现场" : "重新接入"}</button></div>`;
  const list = $("residents");
  if (!save.residents.length)
    list.innerHTML =
      '<p class="muted">这里还没有人。先在检测设施里完成一次解救。</p>';
  list.closest(".panel").classList.add("base-panel");
  save.residents.forEach((r, i) => {
    const el = document.createElement("div");
    el.className = "resident";
    el.innerHTML = `<span>居民 ${i + 1} · ${SINS.find((s) => s.id === r.sin).name} · 负担 ${r.strain}/100</span><p></p><button>${r.mode === "work" ? "安排休息" : "安排生产"}</button>`;
    el.querySelector("p").textContent = r.voice;
    el.querySelector("button").onclick = () => {
      r.mode = r.mode === "work" ? "rest" : "work";
      persist();
      showBase();
    };
    list.append(el);
  });
  for (const [id, name] of [
    ["body", "躯体 +15"],
    ["power", "基础伤害 +12%"],
    ["capacity", "每人每班产出 +2"],
  ]) {
    const lv = save.upgrades[id],
      cost = 20 + lv * 20,
      b = document.createElement("button");
    b.textContent = `${name} · ${cost}材料（${lv}级）`;
    b.disabled = save.currency < cost;
    b.onclick = () => {
      if (save.currency >= cost) {
        save.currency -= cost;
        save.upgrades[id]++;
        if (id === "body" && player) {
          player.maxHp += 15;
          player.hp += 15;
        }
        persist();
        showBase();
      }
    };
    $("upgrades").append(b);
  }
  const workshop = document.createElement("button");
  workshop.textContent = "欲望技能树 · 装配 / 升级";
  workshop.onclick = () =>
    showWorkshop({
      overlay: $("overlay"),
      save,
      design,
      sins: SINS,
      persist,
      back: showBase,
      index: Math.min(selected, save.unlocked - 1),
    });
  $("upgrades").append(workshop);
  const explanation = document.createElement("p");
  explanation.className = "muted";
  explanation.textContent =
    "将欲望维持在不能满足的状态，记录它产生的痛苦。每班30秒，每位工作者产出12材料、负担增加25；达到80后自动休息。休息者不产出材料。探索期间生产继续，每走过一间房，休息者恢复10负担。";
  $("produce").before(explanation);
  $("produce").onclick = () => {
    const error = startShift(save);
    if (error) toast(error);
    persist();
    showBase();
  };
  $("return").onclick = () => {
    if (running) {
      paused = false;
      $("overlay").hidden = true;
    } else begin();
  };
}
SINS.forEach((s, i) => {
  const b = document.createElement("button");
  b.className = "sin";
  b.style.setProperty("--color", s.color);
  b.innerHTML = `${i + 1} ${s.name}<b>0</b><small>欲望强度 / 100</small><i></i>`;
  b.onclick = () => {
    if (i < save.unlocked) {
      selected = i;
      updateHUD();
    }
  };
  $("sins").append(b);
});
function togglePause() {
  if (!running) return;
  paused = !paused;
  $("overlay").hidden = !paused;
  if (paused) {
    $("overlay").innerHTML =
      '<div class="panel"><span class="eyebrow">PAUSED</span><h2>暂停接入</h2><p>现场计时已停止。</p><button id="resume" class="primary">继续</button><button id="settings">声音与画面</button><button id="camp">结束本次接入，回基地</button></div>';
    $("resume").onclick = togglePause;
    $("camp").onclick = confirmWithdrawal;
    $("settings").onclick = showSettings;
  }
}
function showSettings() {
  $("overlay").innerHTML =
    '<div class="panel"><span class="eyebrow">ACCESS / SETTINGS</span><h2>声音与画面</h2><p><label for="volume">音量</label> <output id="volume-label"></output></p><input id="volume" type="range" min="0" max="100" step="1"><p><label><input id="reduce-motion" type="checkbox"> 减少震屏与受击闪光</label></p><p class="muted">移动、弹道和预警保留，避免影响判断。设置会自动保存。</p><button id="settings-back" class="primary">返回暂停菜单</button></div>';
  const volume = $("volume");
  volume.value = Math.round(save.settings.volume * 100);
  $("volume-label").textContent = volume.value + "%";
  volume.oninput = () => {
    save.settings.volume = Number(volume.value) / 100;
    soundscape.setVolume(save.settings.volume);
    $("volume-label").textContent = volume.value + "%";
    persist();
  };
  $("reduce-motion").checked = save.settings.reduceMotion;
  $("reduce-motion").onchange = (e) => {
    save.settings.reduceMotion = e.target.checked;
    persist();
  };
  $("settings-back").onclick = () => {
    paused = false;
    togglePause();
  };
}
function confirmWithdrawal() {
  $("overlay").innerHTML =
    '<div class="panel"><span class="eyebrow">WITHDRAW</span><h2>现在断开连接？</h2><p>已解救的人、能力和升级都会保留。<br>当前罪槽不带回基地；下次从本大关第一室开始。</p><button id="withdraw" class="primary">断开，回基地</button><button id="cancel-withdraw">继续这一轮</button></div>';
  $("withdraw").onclick = () => {
    running = false;
    keys.clear();
    mouse.down = false;
    persist();
    showBase();
  };
  $("cancel-withdraw").onclick = () => {
    paused = false;
    $("overlay").hidden = true;
  };
}
$("start").onclick = () => {
  soundscape.start();
  begin();
};
$("base").onclick = showBase;
$("pause").onclick = togglePause;
const mute = document.createElement("button");
mute.textContent = soundscape.muted ? "声音 关" : "声音 开";
mute.setAttribute("aria-label", "切换声音");
mute.onclick = () => {
  soundscape.setMuted(!soundscape.muted);
  save.settings.muted = soundscape.muted;
  persist();
  mute.textContent = soundscape.muted ? "声音 关" : "声音 开";
};
$("pause").before(mute);
window.addEventListener("keydown", (e) => {
  if (e.target instanceof HTMLInputElement) return;
  const k = e.key.toLowerCase();
  if ([" ", "arrowup", "arrowdown", "arrowleft", "arrowright"].includes(k))
    e.preventDefault();
  keys.add(k);
  if (e.repeat) return;
  if (k === "escape") togglePause();
  if (!running || paused) return;
  if (+k >= 1 && +k <= save.unlocked) {
    selected = +k - 1;
    updateHUD();
  }
  if (k === "q") cast(0);
  if (k === "e") cast(1);
  if (k === "f") interact();
  if (k === " " && dashCD <= 0) {
    const dx = (keys.has("d") ? 1 : 0) - (keys.has("a") ? 1 : 0),
      dy = (keys.has("s") ? 1 : 0) - (keys.has("w") ? 1 : 0),
      stats = passiveStats(save, sin(), { linkNear: !!link });
    walk(
      player,
      dx || dy ? { x: player.x + dx * 200, y: player.y + dy * 200 } : mouse,
      900 * (1 + abilities.value(player, "nextDashDistance")),
      0.16,
    );
    dashCD =
      1.2 *
      Math.max(
        0.3,
        stats.dashRecovery -
          abilities.value(player, "dashRecovery") -
          abilities.value(player, "nextDashRecovery"),
      );
    delete player.buffs?.nextDashDistance;
    delete player.buffs?.nextDashRecovery;
    const rank = P.passiveRank(save, "W12");
    if (rank && abilities.proc(player, "W12", 3))
      abilities.buff(player, "speed", 0.7 + 0.3 * rank, 0.05 + 0.05 * rank);
    player.immune = 0.4;
  }
});
window.addEventListener("keyup", (e) => keys.delete(e.key.toLowerCase()));
window.addEventListener("blur", () => {
  keys.clear();
  mouse.down = false;
  if (running && !paused) togglePause();
});
window.addEventListener("keydown", (e) => {
  if (running && !paused && !e.repeat) {
    const slot = ["r", "t", "g"].indexOf(e.key.toLowerCase());
    if (slot >= 0) cast(slot + 2);
  }
});
canvas.addEventListener("mousemove", (e) => {
  const r = canvas.getBoundingClientRect(),
    scale = Math.min(r.width / W, r.height / H);
  mouse.x = (e.clientX - r.left - (r.width - W * scale) / 2) / scale;
  mouse.y = (e.clientY - r.top - (r.height - H * scale) / 2) / scale;
});
canvas.addEventListener("mousedown", (e) => {
  if (!running || paused) return;
  if (e.button === 0) mouse.down = true;
  if (e.button === 2) inject();
});
window.addEventListener("mouseup", () => (mouse.down = false));
canvas.addEventListener("contextmenu", (e) => e.preventDefault());
function loop(now) {
  const dt = Math.min(0.05, (now - last) / 1000 || 0);
  last = now;
  tick(dt);
  draw();
  requestAnimationFrame(loop);
}
requestAnimationFrame(loop);
window.__game = {
  get state() {
    return {
      player,
      guards,
      humans,
      props,
      bullets,
      stage,
      room,
      tutorial,
      save,
      running,
      paused,
      selected,
      basicCooldown: cooldown,
      orbitCount: orbit.length,
    };
  },
};
