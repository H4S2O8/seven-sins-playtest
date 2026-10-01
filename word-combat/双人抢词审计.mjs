import { readFileSync, writeFileSync } from 'node:fs';

// Acquisition-only audit. It deliberately does not claim to simulate battle.
const words = readFileSync(new URL('./词库.tsv', import.meta.url), 'utf8').trim().split(/\r?\n/).slice(1)
  .map((line) => { const [id, , , rarity] = line.split('\t'); return { id, rarity }; });
const pools = Object.fromEntries(['基础', '进阶', '奇术'].map((r) => [r, words.filter((w) => w.rarity === r).map((w) => w.id)]));
const basics = new Set(pools['基础']);
const templates = [
  ['001','002','064','065','026','015','016'],
  ['001','002','021','015','016'],
  ['001','002','022','015','016'],
  ['001','002','028','015','016'],
];
const strong = ['010','008','002','003','004','014','016','027','038','039','062','020'];
const purge = ['011','031','064','065','026','015','016'];
const routes = [
  ['基本攻击', ['001','002','015','016']],
  ['指定目标', ['064','065','026']],
  ['治疗', ['003','004','014','016']],
  ['集体攻击', ['001','002','027','015','016']],
  ['固定减伤', ['005','013']],
  ['持续减伤', ['005','062','013']],
  ['分流', ['069','063']],
  ['触发反击', ['038','039','074','001','002']],
  ['狂振状态', ['010','090','062']],
  ['牵连状态', ['010','091','062']],
  ['升华状态', ['010','092','062']],
  ['净化限时', purge],
  ['全队伤转疗', strong],
  ['治疗连锁', ['038','041','059','070','075']],
  ['溢出利用', ['036','003','004','038']],
];
let seed = 0x8d4c3a21;
function random() { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return (seed >>> 0) / 4294967296; }
function choose(a) { return a[Math.floor(random() * a.length)]; }
function draw() { const n = random(); return choose(pools[n < .55 ? '基础' : n < .95 ? '进阶' : '奇术']); }
function opening() { const s = new Set(choose(templates)); while (s.size < 12) s.add(choose(pools['基础'])); return s; }
function bag() { let s; do { s = new Set(); while (s.size < 20) s.add(draw()); } while ([...s].filter((id) => basics.has(id)).length < 10); return s; }
function missing(have, need) { return need.filter((id) => !have.has(id)).length; }
function newNeeds(have, offered, need) { return need.filter((id) => !have.has(id) && offered.has(id)).length; }
function add(have, offered) { for (const id of offered) have.add(id); }
function routeScore(have, offered) {
  // Closely approaching several possible routes is rewarded. No prescribed deck.
  const enlarged = new Set([...have, ...offered]);
  return routes.reduce((sum, [, need]) => {
    const before = missing(have, need), after = missing(enlarged, need);
    return sum + (before === 0 ? 0 : (before - after) / (after + 1));
  }, 0);
}
const trials = 10000;
const rows = [];
for (const rounds of [2,4,6,8]) {
  let attackerReady = 0, defenderReady = 0, bothReady = 0, meaningful = 0, offers = 0;
  let generalRoutes = 0, generalChoices = 0;
  for (let t = 0; t < trials; t++) {
    const a = opening(), d = opening(), general = opening();
    for (let r = 1; r <= rounds; r++) {
      const left = bag(), right = bag();
      const aLeft = newNeeds(a,left,strong), aRight = newNeeds(a,right,strong);
      const dLeft = newNeeds(d,left,purge), dRight = newNeeds(d,right,purge);
      if (aLeft !== aRight || dLeft !== dRight) meaningful++;
      offers++;
      const firstA = r % 2 === 1;
      const attackerPicksLeft = firstA ? aLeft >= aRight : !(dLeft >= dRight);
      add(a, attackerPicksLeft ? left : right);
      add(d, attackerPicksLeft ? right : left);
      const gLeft = routeScore(general,left), gRight = routeScore(general,right);
      if (Math.abs(gLeft-gRight) > .25) generalChoices++;
      add(general,gLeft >= gRight ? left : right);
    }
    const ar = missing(a,strong) === 0, dr = missing(d,purge) === 0;
    attackerReady += +ar; defenderReady += +dr; bothReady += +(ar && dr);
    generalRoutes += routes.filter(([, need]) => missing(general,need) === 0).length;
  }
  rows.push({rounds, trials, strongReadyPct: +(100*attackerReady/trials).toFixed(2),
    counterReadyPct: +(100*defenderReady/trials).toFixed(2),
    counterGivenStrongPct: attackerReady ? +(100*bothReady/attackerReady).toFixed(2) : null,
    offersWithDifferentGoalProgressPct: +(100*meaningful/offers).toFixed(2),
    averageCompletedWordSets: +(generalRoutes/trials).toFixed(2),
    generalBagChoiceClearlyDifferentPct: +(100*generalChoices/offers).toFixed(2) });
}
const result = {seed:'0x8d4c3a21', trials, method:'双方各随机发12个基础词，保证一类基础攻击句；每轮两袋各20个互不重复词，基础55%/进阶40%/奇术5%，至少10基础；一方逐轮争夺全队伤转疗所需词，另一方争夺移除公开限时效果的词，轮流先选。只计算持词，未模拟AP、数字预算、施法时机或技能树合法性。一般路线数仅是词集合可得性，不等同于完整合法技能。', rows};
writeFileSync(new URL('./双人抢词结果.json', import.meta.url), JSON.stringify(result,null,2)+'\n');
console.log(rows);
