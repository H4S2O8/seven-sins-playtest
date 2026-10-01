import { readFileSync, writeFileSync } from 'node:fs';

const lines = readFileSync(new URL('./词库.tsv', import.meta.url), 'utf8').trim().split(/\r?\n/);
const words = lines.slice(1).map((line) => {
  const [id, name, category, rarity] = line.split('\t');
  return { id, name, category, rarity };
});
if (words.length !== 100 || new Set(words.map((w) => w.id)).size !== 100) {
  throw new Error(`词库须恰好100个不重复词，实际为${words.length}`);
}
const pools = Object.fromEntries(['基础', '进阶', '奇术'].map((rarity) => [rarity, words.filter((w) => w.rarity === rarity)]));
const basicIds = new Set(pools['基础'].map((word) => word.id));
const weight = [['基础', 0.55], ['进阶', 0.40], ['奇术', 0.05]];
// Opening words are actually dealt; no grammar token is freely available.
const openingTemplates = [
  ['001', '002', '064', '065', '026', '015', '016'],
  ['001', '002', '021', '015', '016'],
  ['001', '002', '022', '015', '016'],
  ['001', '002', '028', '015', '016'],
];
let state = 0x5a17e9b3;
function random() {
  state ^= state << 13;
  state ^= state >>> 17;
  state ^= state << 5;
  return (state >>> 0) / 0x100000000;
}
function draw() {
  const r = random();
  let c = 0;
  let rarity = '奇术';
  for (const [candidate, probability] of weight) {
    c += probability;
    if (r < c) { rarity = candidate; break; }
  }
  const pool = pools[rarity];
  return pool[Math.floor(random() * pool.length)].id;
}
function opening() {
  const template = openingTemplates[Math.floor(random() * openingTemplates.length)];
  const owned = new Set(template);
  while (owned.size < 12) owned.add(pools['基础'][Math.floor(random() * pools['基础'].length)].id);
  return owned;
}
function bag() {
  let result;
  do {
    const unique = new Set();
    while (unique.size < 20) unique.add(draw());
    result = [...unique];
  } while (result.filter((id) => basicIds.has(id)).length < 10);
  return result;
}
const recipes = {
  '可指定目标的基础单体伤害': ['001','002','064','065','026','015','016'],
  '直接减少生命（同义伤害）': ['007','004','015','016','026','065'],
  '移除敌方限时效果': ['011','031','015','016','026','065'],
  '全体伤害转治疗': ['010','008','002','003','004','014','016','027','038','039','062'],
  '溢出治疗造成伤害': ['036','003','004','038','001','002','015','016'],
};

function run(recipe, seat, rounds, trials) {
  const needed = new Set(recipe);
  let successes = 0;
  for (let trial = 0; trial < trials; trial++) {
    const owned = opening();
    for (let round = 1; round <= rounds; round++) {
      const left = bag();
      const right = bag();
      const score = (b) => new Set(b.filter((id) => needed.has(id) && !owned.has(id))).size;
      const first = seat === '总是先选' || (seat === '交替先选' && round % 2 === 1);
      const picked = (score(left) >= score(right)) === first ? left : right;
      for (const id of picked) owned.add(id);
    }
    if ([...needed].every((id) => owned.has(id))) successes++;
  }
  return +(100 * successes / trials).toFixed(2);
}

const trials = 10000;
const results = [];
for (const [recipe, ids] of Object.entries(recipes)) {
  const row = { recipe, ids, trials };
  for (const rounds of [2, 4, 6, 8]) {
    row[`R${rounds}_交替`] = run(ids, '交替先选', rounds, trials);
    row[`R${rounds}_总先`] = run(ids, '总是先选', rounds, trials);
  }
  results.push(row);
}
writeFileSync(new URL('./词袋可得性结果-随机基础起手.json', import.meta.url), JSON.stringify({ seed: '0x5a17e9b3', trials, assumptions: '开局随机发12个基础词，其中按四种模板之一保证能组成基础攻击，非免费语法；每轮两袋各20词，无袋内重复，基础55%/进阶40%/奇术5%，每袋至少10个基础词；先选者挑缺词更多的袋，后选者拿余袋；未模拟对手自己的构筑目标、交易或局中调整。', results }, null, 2) + '\n');
for (const row of results) {
  console.log(`${row.recipe}\t${row.R2_交替}%\t${row.R4_交替}%\t${row.R6_交替}%\t${row.R8_交替}%`);
}
