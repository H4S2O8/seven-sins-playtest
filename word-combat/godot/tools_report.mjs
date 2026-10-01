// 由 audit_ap60.json / audit_ap30.json / avail.json 生成报告里的数据表。
import {readFileSync, writeFileSync} from 'node:fs';
const audit60 = JSON.parse(readFileSync('audit_ap60.json', 'utf8'));
const audit30 = JSON.parse(readFileSync('audit_ap30.json', 'utf8'));
const avail = JSON.parse(readFileSync('avail.json', 'utf8'));
const availOf = (kind, name) => avail.rows.find(r => r.kind === kind && r.name === name);
const pct = x => (x * 100).toFixed(0) + '%';
const stripParen = s => s.replace(/（.*?）/, '');

function classify(row, c) {
  // 返回 {kind:'negate'|'trade'|'reverse'|null, try}
  if (!c.neutralized) return {kind: null};
  const t = c.tries[c.tries.length - 1];
  const base = row.base_score;
  if (t.att_score <= 0.25 * base) return {kind: t.def_score > 0.5 * base ? 'reverse' : 'negate', t};
  return {kind: t.reversed ? 'reverse' : 'trade', t};
}

let md = '';
function section(title, audit) {
  md += `\n### ${title}\n\n`;
  md += '| 进攻组合 | 操作费/起手 | 基线得分 | 词袋齐备 R3 / R6 | 纯化解（拆招费占进攻%）及其词袋可得率 R3 / R6 | 交换 / 反打（费占比） |\n|---|---|---|---|---|---|\n';
  for (const row of audit.results) {
    if (row.base_score === 0) continue;
    const a = availOf('攻', row.attack);
    const neg = [], oth = [];
    for (const c of row.counters) {
      const cl = classify(row, c);
      const nm = stripParen(c.name);
      const av = availOf('守', nm.replace(/·全队·每次→来源|·自身·首次→来源/, m => m) ) || availOf('守', c.name.replace(/（.*?）/, ''));
      if (cl.kind === 'negate') neg.push(`${nm} ${pct(cl.t.frac)}${av ? `（${pct(av.ready[2])}/${pct(av.ready[5])}）` : ''}`);
      else if (cl.kind === 'trade' || cl.kind === 'reverse') oth.push(`${nm} ${pct(cl.t.frac)}${cl.kind === 'reverse' ? '·反打' : ''}`);
    }
    md += `| ${row.attack} | ${row.cost}/${row.windup}秒 | ${row.base_score} | ${a ? pct(a.ready[2]) + ' / ' + pct(a.ready[5]) : '-'} | ${neg.join('；') || '**无**'} | ${oth.join('；') || '—'} |\n`;
  }
}
section('满额行动点（60）：每个进攻都把操作费拉到上限', audit60);
md += '\n> 说明：仅列出基线得分>0 的组合；“纯化解”指进攻方本轮得分降到基线的25%以下；“交换”指双方都得分但分差抹平；“反打”指防守方反而领先。括号里是该拆招的词在第3轮/第6轮结束时凑齐的概率（有针对性抽词）。\n';
section('30 行动点：前期局面', audit30);
writeFileSync('_report_tables.md', md);
console.log('ok', md.length);
