export type Faction = "blood" | "fire" | "name";
export type Kind = "melee" | "ranged";
export type Card = { id: string; name: string; faction: Faction; kind: Kind; attack: number; interval: number; basic: string; skill: string; timing: "start" | "first" | "death"; target: "ally" | "enemy" | "none"; art: string };
const art = { blood: ["WR1","WR2","WR3","WR4","GR1","GR2","GR3","GR4","LU1","LU2"], fire: ["EN1","EN2","EN3","EN4","GL1","GL2","GL3","GL4","A01","A02"], name: ["SL1","SL2","SL3","SL4","PR1","PR2","PR3","PR4","LU3","LU4"] };
const rows: [Faction, string, string, Kind, number, number, string, string, Card["timing"], Card["target"]][] = [
  ["blood","B01","血契侍者","melee",3,7,"有效治疗后得1盾","借命：自伤2，目标治疗4","start","ally"],
  ["blood","B02","红宴司仪","ranged",2,8,"队友受疗后，下刀+1，至多2","分席：群疗2／最低血量者疗4","first","none"],
  ["blood","B03","缝心医师","ranged",2,11,"普攻后前位治疗1","缝合：目标现在及2刻后各治疗2","start","ally"],
  ["blood","B04","伤口诗人","melee",3,9,"受伤后为后位队友提供1盾","开口：消耗自身至多3盾，等量伤害敌前位","first","none"],
  ["blood","B05","殉血卫士","melee",4,8,"普攻后自伤1","挡在前面：目标得3盾，自身首刀晚1刻","start","ally"],
  ["blood","B06","脉搏猎手","melee",3,11,"血量比例高于目标时普攻+1","放血：自伤1，目标敌人受2伤","first","enemy"],
  ["blood","B07","血井看守","ranged",2,9,"记录己方自伤失血，最多4","开井：目标治疗2＋记录量","first","ally"],
  ["blood","B08","红衣继承人","ranged",2,12,"队友一次有效治疗≥2，自己治疗1","承诺：下次自疗改疗前位，数值+2","start","none"],
  ["blood","B09","绯红双生","melee",3,13,"被敌人非致命扣血后恢复1","换肤：攻击−1，自伤后也恢复1","start","none"],
  ["blood","B10","葬礼厨师","ranged",2,10,"队友死亡自己恢复2","最后一席：群疗3／敌前位受4伤","death","none"],
  ["fire","F01","引火童","ranged",2,7,"首刀使目标灼烧1","火种：目标敌人灼烧2","start","enemy"],
  ["fire","F02","炉膛守卫","melee",3,10,"灼烧扣敌血后得1盾","出炉：攻击+1，首刀前消盾伤敌前位","start","none"],
  ["fire","F03","灰烬行者","melee",3,9,"普攻击杀后灼烧下一名敌人1","趁热：敌前位有火则受2伤","first","none"],
  ["fire","F04","焚信人","ranged",2,12,"技能扣血后让目标行动晚1刻","烧毁日程：目标受2伤且晚1刻","start","enemy"],
  ["fire","F05","爆炉工","melee",4,8,"普攻后自伤1","卸压：友方目标得2盾，敌方同槽受2伤","start","ally"],
  ["fire","F06","余温修女","ranged",2,11,"灼烧扣敌血后治疗最低血量队友1","暖焰：治疗目标3／敌前位灼烧2","first","ally"],
  ["fire","F07","烈焰斗士","melee",3,12,"敌人有盾时普攻+1","熔穿：首刀至多2伤穿盾","first","none"],
  ["fire","F08","火线织工","ranged",2,10,"友盾被打破则向敌方灼烧1","引线：目标得3盾，2刻后自伤1","start","ally"],
  ["fire","F09","逐火兽","melee",3,11,"敌方存在灼烧时普攻+1","添柴：按其他着火槽数伤目标，再灼烧1","first","enemy"],
  ["fire","F10","不熄者","melee",3,13,"死亡后全体活敌人灼烧1","余烬之身：攻击+1，首刀前自伤2，亡语集中前位","start","none"],
  ["name","N01","无名见证","ranged",2,8,"友方技能成功输出则得1盾","记住：目标友方下一次输出2刻后回放","start","ally"],
  ["name","N02","空座守门人","melee",3,10,"队友死后前位行动提前1刻","让拍：目标友方提前2刻，自己晚1刻","start","ally"],
  ["name","N03","被删去的王","melee",4,12,"队友死亡，后续攻击−1","废黜：攻击从2起，队友死亡后+1","start","none"],
  ["name","N04","借名者","melee",3,9,"自己盾破后提前1刻","借壳：从友方目标转至多3盾并治疗对方等量","start","ally"],
  ["name","N05","失语审判官","ranged",2,10,"成功推迟敌人后自己得1盾","静默：目标敌人晚2刻","start","enemy"],
  ["name","N06","倒写史官","ranged",2,13,"友方回放后治疗前位1","倒写：回放最近治疗／伤害技能","first","none"],
  ["name","N07","失物招领员","melee",3,11,"队友破盾则自己得2盾","归还：转自己至多3盾给目标并让其提前1刻","first","ally"],
  ["name","N08","不存在的客人","melee",3,8,"首次敌方普攻伤害−1","缺席：得3盾，首刀晚2刻","first","none"],
  ["name","N09","墓志铭匠","ranged",2,12,"队友死亡，下一刀+1，最多2","刻名：标记目标友方，死亡时敌前位受其攻击值伤","start","ally"],
  ["name","N10","昨日余像","melee",3,7,"普攻后得1盾","改稿：自伤2并强化前两刀／得4盾并削弱前两刀","start","none"],
];
export const CARDS: Card[] = rows.map(([faction,id,name,kind,attack,interval,basic,skill,timing,target],i)=>({faction,id,name,kind,attack,interval,basic,skill,timing,target,art:art[faction][i%10]}));
export const BY_ID = Object.fromEntries(CARDS.map(c=>[c.id,c])) as Record<string,Card>;
export const BASES = [
  {id:"P01",name:"余烬炉",text:"普攻击杀的溢伤至多2点，追击下一名敌人。"},
  {id:"P02",name:"血债簿",text:"被敌人扣血后，下一刀加1。"},
  {id:"P03",name:"无名剧院",text:"友方行动提前时，该人得1盾。"},
  {id:"P04",name:"圣餐桌",text:"每2点溢疗，使受疗者下一刀加1，至多2。"},
  {id:"P05",name:"逆旅门",text:"非致命伤跌过半血时，下一刀提前2刻。"},
  {id:"P06",name:"未寄之信",text:"首次正输出技能延迟2刻，数值变为1.5倍。"},
];
export const FIELDS = [
  ["双倍回流","转盾时，接收量翻倍，额外至多3。"],["余波","技能扣敌血后，后方最近敌人受1伤。"],["火借风势","新灼烧也使后方最近敌人灼烧1。"],["急燃","灼烧变成立即的一次伤害。"],["慢火长明","灼烧间隔变3刻，每份伤害+1。"],
  ["薄冰护甲","得盾少1；破盾时敌前位受2伤。"],["隔热层","盾挡非普攻伤害时，1盾抵2伤。"],["卸甲进攻","每失去2盾，下刀+1，至多2。"],["伤口记忆","扣血后下一次治疗+1。"],["血不能白流","自伤扣血后，前位得等量盾，至多2。"],
  ["过量处方","溢疗至多2点变成护盾。"],["轻甲快行","得盾少1；仍得盾则行动提前1刻。"],["谢幕掌声","随从死亡后，队友行动提前1刻。"],["接班人","首次站到最前时，无盾得2盾，否则行动提前1刻。"],["隔席相赠","给予其他友方治疗或盾时，跨槽每格+1。"],
  ["余音","技能输出一半立即，一半2刻后。"],["缓冲地带","盾挡伤后行动提前2刻。"],["刀口朝外","前位自伤改为伤害敌前位。"],["最后一寸","普攻溢伤至多2点变自身盾。"],["急行军","有效行动提前额外+1刻，随后自伤1。"],
].map(([name,text],i)=>({id:`E${String(i+1).padStart(2,"0")}`,name,text}));
