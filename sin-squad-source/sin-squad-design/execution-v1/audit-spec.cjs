const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const base = __dirname;
const parent = path.dirname(base);
const registry = JSON.parse(fs.readFileSync(path.join(parent, 'catalog.json'), 'utf8'));
const entries = registry.entries;
const failures = [];
const checks = [];
function check(label, ok, details = '') { checks.push({label, ok, details}); if(!ok) failures.push(label); }
const mapping = [
  ['04-98人物演出表.md', /^(WR|GR|GL|EN|SL|LU|PR)\d{2}$/],
  ['05-装备场地与界面表现.md', /^(EQ|FX|AR|PE)\d{2}$/],
  ['09-30条规则执行表.md', /^VC\d{2}$/],
];
check('catalog contains 298 unique entries', entries.length === 298 && new Set(entries.map(e => e.id)).size === 298);
for (const [file, re] of mapping) {
  const text = fs.readFileSync(path.join(base,file),'utf8');
  const rows = text.split(/\r?\n/).filter(l => /^\|\s*[A-Z]{2}\d{2}(?:\s|\|)/.test(l));
  const rowID = l => l.match(/^\|\s*([A-Z]{2}\d{2})/)[1];
  const ids = rows.map(rowID);
  const wanted = entries.filter(e => re.test(e.id));
  const missing = wanted.filter(e => !ids.includes(e.id)).map(e => e.id);
  const duplicates = ids.filter((id,i)=>ids.indexOf(id)!==i);
  check(file + ': all IDs once', missing.length === 0 && duplicates.length === 0 && ids.length === wanted.length, JSON.stringify({count:ids.length,missing,duplicates}));
  const mismatch = wanted.filter(e => !rows.find(l=>rowID(l)===e.id)?.includes(e.name)).map(e=>`${e.id}:${e.name}`);
  check(file + ': canonical names', mismatch.length===0, mismatch.join(', '));
}
const required = ['00-先读这个.md','01-镜头位置与素材.md','02-流程下注与胜负.md','03-全部动作与时间线.md','04-98人物演出表.md','05-装备场地与界面表现.md','06-代码接口与交付结构.md','07-零基础教程脚本.md','08-实施工单与验收.md','09-30条规则执行表.md','执行入口.txt','进度.md','reference/table-approved-A.png'];
for(const file of required) check('exists '+file,fs.existsSync(path.join(base,file)));
const ac = fs.readFileSync(path.join(base,'03-全部动作与时间线.md'),'utf8');
check('AC01-AC50 all documented', Array.from({length:50},(_,i)=>'AC'+String(i+1).padStart(2,'0')).every(id=>ac.includes(id)));
const t = fs.readFileSync(path.join(base,'07-零基础教程脚本.md'),'utf8');
check('T01-T35 all documented', Array.from({length:35},(_,i)=>'T'+String(i+1).padStart(2,'0')).every(id=>t.includes(id)));
const locks={
 '00-战斗约定.md':'B544791BE4018BA8EFACB83AFD2FD6B1BF2F2CE5D05E49A47E93F7FEB0665697',
 '01-人物.md':'1CE508E93AE694D80DD55CC0F113AA8A6B82E2DBBD3AF81A2622236843704BA5',
 '02-装备与槽位.md':'5E7A8EC39406C64013C15F867DBE61DA4639BE7CBA3611E0C92AC144703E2DBD',
 '03-胜利规则.md':'D3AC501AD84E6B2ED1F102F481DDAF87AF55036815313FA281E96DBD25FC41D1',
 '04-场地与公共效果.md':'CCA7D70FDE065E63707D590F6D8272B8CCF81CB55007822FADF49CC8E7B7FFD9'
};
for(const [file, hash] of Object.entries(locks)) check('source unchanged '+file, crypto.createHash('sha256').update(fs.readFileSync(path.join(parent,file))).digest('hex').toUpperCase()===hash);
console.log(JSON.stringify({scope:'SPEC_ONLY_NOT_GAME_ACCEPTANCE',checks,failures},null,2));
process.exitCode = failures.length ? 1 : 0;
