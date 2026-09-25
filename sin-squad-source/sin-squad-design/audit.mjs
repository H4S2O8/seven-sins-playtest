import fs from 'node:fs';
import path from 'node:path';
const root=import.meta.dirname;
const {entries,counts}=JSON.parse(fs.readFileSync(path.join(root,'catalog.json'),'utf8'));
const issues=[];
for(const c of entries){
 const need=['WR','GR','GL','EN','SL','LU','PR'].includes(c.category)?['面板：','能力：','用法：','弱点：']:['EQ','FX'].includes(c.category)?['效果：','适配：','取舍：']:c.category==='VC'?['判定：','战术：','应对：']:c.category==='AR'?['机制：','相性：','演出：']:['效果：','相性：','演出：'];
 for(const f of need)if(!c.text.includes(f))issues.push(`${c.id} 缺字段 ${f}`);
 if(/\b(?:TODO|TBD|xxx)\b|待补|待填写/i.test(c.text))issues.push(`${c.id} 含占位符`);
}
const exact=new Map();for(const c of entries){let ability=(c.text.match(/(?:能力|效果|机制|判定)：([^\n]+)/)||[])[1];if(!ability)continue;ability=ability.replace(/\s/g,'');if(exact.has(ability))issues.push(`${c.id} 与 ${exact.get(ability)} 正文完全相同`);else exact.set(ability,c.id);}
const result={checkedAt:new Date().toISOString(),counts,total:entries.length,structureIssues:issues,limits:['本检查不模拟战斗','不同能力文本不等于不同体验','没有用面板大小代替上下位判定','需要人工交叉审阅与后续对战验证']};
fs.writeFileSync(path.join(root,'audit-result.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));if(issues.length)process.exitCode=1;
