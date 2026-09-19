import {CARDS, PROFESSIONS} from './cards.js?v=e38f7686abea';
const neutralSets=[['N01','N03','N05','N09','N11','N15'],['N02','N07','N10','N12','N14','N17'],['N04','N08','N13','N18','N19','N20']];
export function preset(profession,variant=0){
 const ids=Object.values(CARDS).filter(c=>c.profession===profession&&c.kind==='main').map(c=>c.id);
 const preferred=neutralSets[variant];
 const banned=profession==='PR'?['N04','N08','N13','N18','N20']:[];
 const neutrals=[...preferred,...neutralSets.flat()].filter((id,i,a)=>a.indexOf(id)===i&&!banned.includes(id)).slice(0,6);
 const entries=[...ids,...neutrals].map(id=>({id,copies:3}));
 const rules=[`${profession}-R${variant+1}`,`${profession}-R${variant===2?5:4}`];
 entries.push(...rules.map(id=>({id,copies:profession==='PR'?3:2})));
 if(profession==='PR')entries.push({id:neutrals.includes('N16')?'N06':'N16',copies:2});
 else entries.push({id:['U01','U03','U05'][variant],copies:2},{id:'U06',copies:2});
 return entries;
}
export const PRESETS=Object.keys(PROFESSIONS).flatMap(profession=>['进攻试作','生存试作','资源试作'].map((name,i)=>({id:`${profession}-${i}`,name:`${PROFESSIONS[profession]} · ${name}`,profession,entries:preset(profession,i)})));
