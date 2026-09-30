/** Generated from docs/blood-fire-forgotten-combos.md. Run npm run build:blood-fire-combos. */
export type ComboRoute = { id: string; name: string; chapter: string; members: string[]; attackers: string[]; condition: string };
export const COMBO_ROUTES: ComboRoute[] = [
  {
    "id": "001",
    "name": "红契入井",
    "chapter": "C01",
    "members": [
      "B01",
      "B07"
    ],
    "attackers": [],
    "condition": "侍者开战自伤2被记入血井，看守首次行动可疗4；侍者的伤若被盾挡住则少存水。"
  },
  {
    "id": "002",
    "name": "殉道蓄水",
    "chapter": "C01",
    "members": [
      "B05",
      "B07",
      "N02"
    ],
    "attackers": [],
    "condition": "守门人催卫士先攻击产生自伤，看守6刻开井回收；必须让卫士先于看守行动，不能空算记录。"
  },
  {
    "id": "003",
    "name": "改稿余粮",
    "chapter": "C01",
    "members": [
      "N10",
      "B07"
    ],
    "attackers": [],
    "condition": "余像选进攻开战自伤2，血井把它记成额外2治疗；选防御形态则没有这条入口。"
  },
  {
    "id": "004",
    "name": "红契留宴",
    "chapter": "C01",
    "members": [
      "B01",
      "B02"
    ],
    "attackers": [],
    "condition": "侍者自伤后由司仪首次行动治疗，司仪因此积下一刀伤害；侍者不能已被其他治疗补满。"
  },
  {
    "id": "005",
    "name": "猎手缝伤",
    "chapter": "C01",
    "members": [
      "B06",
      "B03"
    ],
    "attackers": [],
    "condition": "猎手首次技能自伤，后续医师普攻治疗承接前位猎手；猎手须是当前前位或早期缝合目标。"
  },
  {
    "id": "006",
    "name": "裂炉存井",
    "chapter": "C01",
    "members": [
      "F05",
      "B07",
      "N02"
    ],
    "attackers": [],
    "condition": "催前排工人提前普攻，自伤先入井，再由看守治疗；没有时间差就只能得到保底2。"
  },
  {
    "id": "007",
    "name": "双生借血",
    "chapter": "C01",
    "members": [
      "B01",
      "B09"
    ],
    "attackers": [],
    "condition": "侍者治疗变形双生先前的非致命伤，双生自己也恢复，分开承担救急与续航；需先有伤口。"
  },
  {
    "id": "008",
    "name": "血井归席",
    "chapter": "C01",
    "members": [
      "N10",
      "B07",
      "P04"
    ],
    "attackers": [],
    "condition": "余像开战伤2存井，看守向满血角色疗4，换下一刀+2；以真实自伤换爆发，不是白送。"
  },
  {
    "id": "009",
    "name": "医师开宴",
    "chapter": "C02",
    "members": [
      "B03",
      "B02"
    ],
    "attackers": [],
    "condition": "医师持续治疗前排第三人，司仪逐次积伤害并从后排兑现；治疗司仪自己不触发司仪基础。"
  },
  {
    "id": "010",
    "name": "余温举杯",
    "chapter": "C02",
    "members": [
      "F06",
      "B02"
    ],
    "attackers": [],
    "condition": "修女从敌方烧伤治疗另一伤员，司仪加伤；需要独立火源或修女先选点火。"
  },
  {
    "id": "011",
    "name": "双生祝酒",
    "chapter": "C02",
    "members": [
      "B09",
      "B02"
    ],
    "attackers": [],
    "condition": "双生被非致命伤后自疗，司仪获得攻击加成；常态一次，变形可多次，但加成都有上限。"
  },
  {
    "id": "012",
    "name": "遗宴出刀",
    "chapter": "C02",
    "members": [
      "B10",
      "B02"
    ],
    "attackers": [],
    "condition": "厨师亡语群疗确实救到司仪之外的人，司仪下一刀增强；只剩司仪则无基础加成。"
  },
  {
    "id": "013",
    "name": "红契烛刀",
    "chapter": "C02",
    "members": [
      "B01",
      "P04"
    ],
    "attackers": [],
    "condition": "借命对满血友槽疗4，受疗者下一刀+2；侍者承担2自伤，输出收益落在被疗者。"
  },
  {
    "id": "014",
    "name": "回井点烛",
    "chapter": "C02",
    "members": [
      "B07",
      "P04"
    ],
    "attackers": [],
    "condition": "血井疗6用于满血目标，受上限最多存+2伤害；不要把多余取整宣称为+3。"
  },
  {
    "id": "015",
    "name": "分席烈酒",
    "chapter": "C02",
    "members": [
      "B02",
      "P04"
    ],
    "attackers": [],
    "condition": "司仪群疗满血三人各2，三人下一刀各+1；比集中疗4只强化一人更分散，也更怕人先死。"
  },
  {
    "id": "016",
    "name": "倒写宴辞",
    "chapter": "C02",
    "members": [
      "N06",
      "B02"
    ],
    "attackers": [],
    "condition": "史官回放其他人的治疗，司仪受益；原技能记录需来自第三人，回放自身技能不能造记录循环。"
  },
  {
    "id": "017",
    "name": "童火长灯",
    "chapter": "C03",
    "members": [
      "F01",
      "F06"
    ],
    "attackers": [],
    "condition": "火种两次扣血给修女两次治疗机会；敌人盾全挡会断供。"
  },
  {
    "id": "018",
    "name": "暖焰慢炖",
    "chapter": "C03",
    "members": [
      "F06",
      "E05"
    ],
    "attackers": [],
    "condition": "修女自己点火每份多1伤、延后结算，基础在真实伤员出现后回血；长等待也可能来不及。"
  },
  {
    "id": "019",
    "name": "灰路取暖",
    "chapter": "C03",
    "members": [
      "F03",
      "F06"
    ],
    "attackers": [],
    "condition": "行者普攻击杀续火，修女利用继任敌人烧伤治疗己方；技能击杀不续火。"
  },
  {
    "id": "020",
    "name": "碎甲围炉",
    "chapter": "C03",
    "members": [
      "F08",
      "F06"
    ],
    "attackers": [],
    "condition": "织工因友方破盾给敌人点火，修女从后续灼烧回收生命；破盾不是主动消耗。"
  },
  {
    "id": "021",
    "name": "不熄晚祷",
    "chapter": "C03",
    "members": [
      "F10",
      "F06"
    ],
    "attackers": [],
    "condition": "不熄者死亡群烧，为修女提供最多三次基础治疗；修女须仍活，不可无限奶。"
  },
  {
    "id": "022",
    "name": "旧火新暖",
    "chapter": "C03",
    "members": [
      "N06",
      "F01",
      "F06"
    ],
    "attackers": [],
    "condition": "史官回放火种的D输出，在原槽再制造定时伤害，修女利用它回血；原槽无人则落空。"
  },
  {
    "id": "023",
    "name": "急火短祷",
    "chapter": "C03",
    "members": [
      "F06",
      "E04"
    ],
    "attackers": [],
    "condition": "修女点火立即造成合并灼烧伤害，马上触发一次治疗，换取急救；由两次潜在治疗降为一次。"
  },
  {
    "id": "024",
    "name": "借书生火",
    "chapter": "C03",
    "members": [
      "F01",
      "N01",
      "F06"
    ],
    "attackers": [],
    "condition": "见证重放火种增加有效烧伤机会，修女救人；基础三次上限使更多火不等于无限恢复。"
  },
  {
    "id": "025",
    "name": "借壳抢拍",
    "chapter": "C04",
    "members": [
      "F08",
      "N04"
    ],
    "attackers": [],
    "condition": "织工直接给借名者盾，盾被打破让其提前行动；这是破盾路径，不要求借壳技能开启。"
  },
  {
    "id": "026",
    "name": "缝伤成火",
    "chapter": "C04",
    "members": [
      "B04",
      "F08"
    ],
    "attackers": [],
    "condition": "诗人实际受伤给后排1盾，该盾破后织工点火；需后排确实被伤害触及。"
  },
  {
    "id": "027",
    "name": "卫士借刃",
    "chapter": "C04",
    "members": [
      "B05",
      "N04"
    ],
    "attackers": [],
    "condition": "卫士给借名者3盾，自身慢1刻，借名者之后破盾快1刻；延迟与提前发生在不同人。"
  },
  {
    "id": "028",
    "name": "遗失火花",
    "chapter": "C04",
    "members": [
      "N07",
      "F08"
    ],
    "attackers": [],
    "condition": "队友盾破给招领员2盾，招领员盾后来再破又触发织工火；两次破盾消耗真实盾。"
  },
  {
    "id": "029",
    "name": "回声碎甲",
    "chapter": "C04",
    "members": [
      "N01",
      "F08",
      "N04"
    ],
    "attackers": [],
    "condition": "引线及其回放两次供盾，若分开被打破可令借名者两次提前；若堆成一层则只有一次破盾。"
  },
  {
    "id": "030",
    "name": "薄冰借拍",
    "chapter": "C04",
    "members": [
      "N04",
      "E06"
    ],
    "attackers": [],
    "condition": "外部盾缩水更易破，破盾同时提前借名者并打敌2；原供盾只有1会变0而失败。"
  },
  {
    "id": "031",
    "name": "薄冰引火",
    "chapter": "C04",
    "members": [
      "F08",
      "E06"
    ],
    "attackers": [],
    "condition": "引线3变2盾，破后有场地2伤与织工定时火，攻防变得更尖锐。"
  },
  {
    "id": "032",
    "name": "接班碎影",
    "chapter": "C04",
    "members": [
      "N04",
      "E14"
    ],
    "attackers": [],
    "condition": "无盾借名者第一次接战得2盾，后来破盾提前行动；已有盾时场地直接给提前，是另一分支。"
  },
  {
    "id": "033",
    "name": "王刃过境",
    "chapter": "C05",
    "members": [
      "N03",
      "P01"
    ],
    "attackers": [],
    "condition": "常态王4伤打残血前位，自己的溢出份额继续伤害下一人；多人集火不能重复领全部溢出。"
  },
  {
    "id": "034",
    "name": "殉道贯阵",
    "chapter": "C05",
    "members": [
      "B05",
      "P01"
    ],
    "attackers": [],
    "condition": "卫士高单伤产生溢出，延续到后排；自伤可能限制它之后的轮数。"
  },
  {
    "id": "035",
    "name": "裂炉穿堂",
    "chapter": "C05",
    "members": [
      "F05",
      "P01"
    ],
    "attackers": [],
    "condition": "工人技能压血后用4伤普攻产生溢出；技能自己的溢出不触发底板。"
  },
  {
    "id": "036",
    "name": "猎手追血",
    "chapter": "C05",
    "members": [
      "B06",
      "P01"
    ],
    "attackers": [],
    "condition": "猎手先技能压前位，再用比例加伤争取溢出；自伤和敌疗可能改变比例。"
  },
  {
    "id": "037",
    "name": "披火破阵",
    "chapter": "C05",
    "members": [
      "F09",
      "P01"
    ],
    "attackers": [],
    "condition": "待发火使逐火兽刀+1，收残人后余烬穿下一个；必须攻击时仍有待发火。"
  },
  {
    "id": "038",
    "name": "影刀织衣",
    "chapter": "C05",
    "members": [
      "N10",
      "E19"
    ],
    "attackers": [],
    "condition": "进攻抉择前两刀+1，击杀溢出转盾补自伤后的防护。"
  },
  {
    "id": "039",
    "name": "烬炉双收",
    "chapter": "C05",
    "members": [
      "N03",
      "P01",
      "E19"
    ],
    "attackers": [],
    "condition": "同一次归属王的溢出既打下一人又给王盾，两个结果各至多2。"
  },
  {
    "id": "040",
    "name": "炉卫出征",
    "chapter": "C05",
    "members": [
      "F02",
      "E19"
    ],
    "attackers": [],
    "condition": "变形后普攻+1，溢出变盾，供未来防御；首次消耗盾的技能伤害不触发此场地。"
  },
  {
    "id": "041",
    "name": "契约外衣",
    "chapter": "C06",
    "members": [
      "B01",
      "E11"
    ],
    "attackers": [],
    "condition": "借命治疗满血队友变2盾，自身留下自伤；选择自己会先填真实伤口，溢出较少。"
  },
  {
    "id": "042",
    "name": "缝合双衣",
    "chapter": "C06",
    "members": [
      "B03",
      "E11"
    ],
    "attackers": [],
    "condition": "两段2治疗在满血时各给2盾，期间若被伤害消耗可补第二层；不是疗4一次至多2盾。"
  },
  {
    "id": "043",
    "name": "双席披风",
    "chapter": "C06",
    "members": [
      "B02",
      "E11"
    ],
    "attackers": [],
    "condition": "群疗可给三个满血人各2盾，范围比集中疗更广；有伤口时优先回实血。"
  },
  {
    "id": "044",
    "name": "井口铸甲",
    "chapter": "C06",
    "members": [
      "B07",
      "E11"
    ],
    "attackers": [],
    "condition": "看守满血治疗至多造2盾，储太多水会溢出浪费，需权衡目标。"
  },
  {
    "id": "045",
    "name": "继承盛杯",
    "chapter": "C06",
    "members": [
      "B08",
      "E11"
    ],
    "attackers": [],
    "condition": "承诺将治疗改给满血前位且+2，转换成前位盾；原本后排自己不再得疗。"
  },
  {
    "id": "046",
    "name": "暖焰战衣",
    "chapter": "C06",
    "members": [
      "F06",
      "E11"
    ],
    "attackers": [],
    "condition": "暖焰选治疗满血角色3变2盾，基础的小治疗每次最多转1盾。"
  },
  {
    "id": "047",
    "name": "墓宴裹身",
    "chapter": "C06",
    "members": [
      "B10",
      "E11"
    ],
    "attackers": [],
    "condition": "厨师亡语给幸存满血者各造2盾，为下一波普攻准备。"
  },
  {
    "id": "048",
    "name": "圣餐盔甲",
    "chapter": "C06",
    "members": [
      "B01",
      "P04",
      "E11"
    ],
    "attackers": [],
    "condition": "满血4治疗同时给受疗者下一刀+2与2盾，实血代价仍由侍者支付。"
  },
  {
    "id": "049",
    "name": "影甲借名",
    "chapter": "C07",
    "members": [
      "N10",
      "N04"
    ],
    "attackers": [],
    "condition": "余像防御抉择得4盾，借名者取3盾并治疗余像3；余像满血时治疗需溢疗组件才有额外用途。"
  },
  {
    "id": "050",
    "name": "借壳双衣",
    "chapter": "C07",
    "members": [
      "N04",
      "E01"
    ],
    "attackers": [],
    "condition": "从外部供盾者实际转3，自己得6盾，原人只治疗3；接收放大不偷改治疗计数。"
  },
  {
    "id": "051",
    "name": "归物成双",
    "chapter": "C07",
    "members": [
      "N07",
      "E01"
    ],
    "attackers": [],
    "condition": "招领员把已获得的2盾转出，队友得4盾并提前1；招领员自身失去2盾。"
  },
  {
    "id": "052",
    "name": "卫衣归还",
    "chapter": "C07",
    "members": [
      "B05",
      "N07"
    ],
    "attackers": [],
    "condition": "卫士开战给招领员3盾，招领员首次行动转给另一核心并催1刻；中继有自己失盾的成本。"
  },
  {
    "id": "053",
    "name": "引线借名",
    "chapter": "C07",
    "members": [
      "F08",
      "N04"
    ],
    "attackers": [],
    "condition": "引线给第三人盾，借名者开战转盾；定时自伤仍打原槽，不能随盾搬走。"
  },
  {
    "id": "054",
    "name": "裂炉借壳",
    "chapter": "C07",
    "members": [
      "F05",
      "N04"
    ],
    "attackers": [],
    "condition": "卸压给其他人2盾，借名者把它转到承伤位并回疗来源；卸压的敌伤不参与转移。"
  },
  {
    "id": "055",
    "name": "归物隔席",
    "chapter": "C07",
    "members": [
      "N07",
      "E15"
    ],
    "attackers": [],
    "condition": "招领员向隔两槽队友转2盾，接收额外+2成4且提前1；不提高源方扣盾量。"
  },
  {
    "id": "056",
    "name": "双流圣餐",
    "chapter": "C07",
    "members": [
      "N04",
      "P04",
      "E01"
    ],
    "attackers": [],
    "condition": "借壳放大转入盾，同时对满血来源疗3变下一刀+1；一份盾兼顾两个位置。"
  },
  {
    "id": "057",
    "name": "厨刀墓铭",
    "chapter": "C08",
    "members": [
      "B10",
      "N09"
    ],
    "attackers": [],
    "condition": "厨师亡语伤害4，刻名再按印刷2伤补一段；每段重新按当前前位规则选择合法目标。"
  },
  {
    "id": "058",
    "name": "灰名长存",
    "chapter": "C08",
    "members": [
      "F10",
      "N09"
    ],
    "attackers": [],
    "condition": "不熄者死时铺火，刻名按印刷3先打即时伤，形成即时与延迟两段推进。"
  },
  {
    "id": "059",
    "name": "王的讣告",
    "chapter": "C08",
    "members": [
      "N03",
      "N09"
    ],
    "attackers": [],
    "condition": "王被刻名后死亡，按印刷4伤，不因生前形态或减伤害改成2。"
  },
  {
    "id": "060",
    "name": "殉卫留印",
    "chapter": "C08",
    "members": [
      "B05",
      "N09"
    ],
    "attackers": [],
    "condition": "卫士输出后退场，留下4伤刻名；它的自伤致死也正常触发。"
  },
  {
    "id": "061",
    "name": "遗宴承王",
    "chapter": "C08",
    "members": [
      "B10",
      "N03"
    ],
    "attackers": [],
    "condition": "厨师死亡治疗变形王并使其后续普攻+1；要王确实有伤才同时获得两端收益。"
  },
  {
    "id": "062",
    "name": "不熄掌声",
    "chapter": "C08",
    "members": [
      "F10",
      "E13"
    ],
    "attackers": [],
    "condition": "不熄者死亡铺火并催全部队友1刻，让活人更早打出后续伤害。"
  },
  {
    "id": "063",
    "name": "空座接席",
    "chapter": "C08",
    "members": [
      "B10",
      "N02"
    ],
    "attackers": [],
    "condition": "厨师死时群疗，守门人基础催当前前位1刻；被救者可以更早兑现攻击。"
  },
  {
    "id": "064",
    "name": "遗宴点烛",
    "chapter": "C08",
    "members": [
      "B10",
      "P04"
    ],
    "attackers": [],
    "condition": "亡语疗3给满血幸存者，各换下一刀+1；不是全队溢疗合并算。"
  },
  {
    "id": "065",
    "name": "重寄火种",
    "chapter": "C09",
    "members": [
      "N01",
      "F01"
    ],
    "attackers": [],
    "condition": "火种被记录后再排两份定时伤害，后槽有活人时稳定扩大伤害量。"
  },
  {
    "id": "066",
    "name": "红契复签",
    "chapter": "C09",
    "members": [
      "N01",
      "B01"
    ],
    "attackers": [],
    "condition": "借命治疗4被重放一次，不再自伤2；若目标已死则空槽部分失效。"
  },
  {
    "id": "067",
    "name": "双焚日程",
    "chapter": "C09",
    "members": [
      "N01",
      "F04"
    ],
    "attackers": [],
    "condition": "重放烧毁日程的伤害，可再次伤敌；同来源A同周期受限，不宣称再次无限推迟。"
  },
  {
    "id": "068",
    "name": "二次暖席",
    "chapter": "C09",
    "members": [
      "N01",
      "F06"
    ],
    "attackers": [],
    "condition": "记录暖焰的已选输出，再疗3或再发火；不会把未选分支也复制。"
  },
  {
    "id": "069",
    "name": "旧伤重写",
    "chapter": "C09",
    "members": [
      "N06",
      "B06"
    ],
    "attackers": [],
    "condition": "猎手先行动留下2伤记录，史官后行动回放伤害；需要史官被推迟或猎手被提前到史官之前。"
  },
  {
    "id": "070",
    "name": "重述挽歌",
    "chapter": "C09",
    "members": [
      "N01",
      "B10"
    ],
    "attackers": [],
    "condition": "记录厨师亡语群疗，死亡后2刻再疗；来源死亡不取消待发包。"
  },
  {
    "id": "071",
    "name": "双份卸压",
    "chapter": "C09",
    "members": [
      "N01",
      "F05"
    ],
    "attackers": [],
    "condition": "重放卸压的2盾和2伤，各落原槽；攻守两端可分别失效，不额外自伤。"
  },
  {
    "id": "072",
    "name": "旧书新契",
    "chapter": "C09",
    "members": [
      "N06",
      "B01"
    ],
    "attackers": [],
    "condition": "史官选择治疗回放开战借命4，基础另给当前前位1；两次治疗对象可能不同。"
  },
  {
    "id": "073",
    "name": "焚书先刀",
    "chapter": "C10",
    "members": [
      "F04",
      "B05"
    ],
    "attackers": [],
    "condition": "焚信让敌方首刀晚1～2刻，卫士争取先打4伤；若敌原本更慢，须核对是否真的新增优势。"
  },
  {
    "id": "074",
    "name": "静默猎杀",
    "chapter": "C10",
    "members": [
      "N05",
      "B06"
    ],
    "attackers": [],
    "condition": "审判官延后危险敌人，猎手在其出手前点后槽或补前槽；不是封掉对方基础。"
  },
  {
    "id": "075",
    "name": "无言灰路",
    "chapter": "C10",
    "members": [
      "F04",
      "F03"
    ],
    "attackers": [],
    "condition": "推迟敌人让行者先普攻完成击杀并续火；趁热仍需其他待发火，不能把焚信伤害当火。"
  },
  {
    "id": "076",
    "name": "拖拍续火",
    "chapter": "C10",
    "members": [
      "N05",
      "F01"
    ],
    "attackers": [],
    "condition": "敌人迟2刻出手，让火种先结算一份甚至完成击杀；已发出的敌火不受推迟影响。"
  },
  {
    "id": "077",
    "name": "判后急焚",
    "chapter": "C10",
    "members": [
      "N05",
      "F06"
    ],
    "attackers": [],
    "condition": "对手首次行动被延后，修女先暖焰治疗或点火，改变那一刀前的生命线。"
  },
  {
    "id": "078",
    "name": "无言借名",
    "chapter": "C10",
    "members": [
      "N05",
      "N04"
    ],
    "attackers": [],
    "condition": "敌人晚刀期间，借名者保住盾等自己的慢普攻；要时间改变确实避免提前被击杀。"
  },
  {
    "id": "079",
    "name": "烧掉宴时",
    "chapter": "C10",
    "members": [
      "F04",
      "B02"
    ],
    "attackers": [],
    "condition": "压住敌人首次行动技能，司仪群疗先落地，再由后续普攻击穿；敌技能若开战已发则无此阻止效果。"
  },
  {
    "id": "080",
    "name": "审判刻名",
    "chapter": "C10",
    "members": [
      "N05",
      "N09"
    ],
    "attackers": [],
    "condition": "推迟敌方收割，让被刻名友方先打一刀再死，随后亡语补伤；不能仅因二人在场授章。"
  },
  {
    "id": "081",
    "name": "让拍趁热",
    "chapter": "C11",
    "members": [
      "N02",
      "F03"
    ],
    "attackers": [],
    "condition": "把后槽行者首刀10催到8，接引火童6刻普攻留下的火；催到火源出现前反而可能失去趁热。"
  },
  {
    "id": "082",
    "name": "炉卫早锤",
    "chapter": "C11",
    "members": [
      "N02",
      "F02"
    ],
    "attackers": [],
    "condition": "催变形炉卫早执行消耗盾爆发；需第三方预先供盾，不能靠已失去的基础自攒。"
  },
  {
    "id": "083",
    "name": "席间催客",
    "chapter": "C11",
    "members": [
      "N02",
      "B02"
    ],
    "attackers": [],
    "condition": "司仪从6到4刻先群疗，挽救将吃首波普攻的人；全满时原生收益要靠溢疗组件。"
  },
  {
    "id": "084",
    "name": "引猎抢拍",
    "chapter": "C11",
    "members": [
      "N02",
      "B06"
    ],
    "attackers": [],
    "condition": "催猎手先放血击杀低血后槽，可能直接取消其第一刀；需目标血盾合适。"
  },
  {
    "id": "085",
    "name": "提前缝心",
    "chapter": "C11",
    "members": [
      "N02",
      "B03"
    ],
    "attackers": [],
    "condition": "医师提前普攻带来前位1治疗，并较早开始下一周期；只提前开战缝合是不成立的说法。"
  },
  {
    "id": "086",
    "name": "提前开井",
    "chapter": "C11",
    "members": [
      "N02",
      "B07"
    ],
    "attackers": [],
    "condition": "催看守提前救命，但必须开战已有自伤记录；否则牺牲储量换速度。"
  },
  {
    "id": "087",
    "name": "轻甲开席",
    "chapter": "C11",
    "members": [
      "B02",
      "E12"
    ],
    "attackers": [],
    "condition": "外部盾达到2以上触发轻甲提前，司仪更早疗人；1盾被减0无提前。"
  },
  {
    "id": "088",
    "name": "无名双幕",
    "chapter": "C11",
    "members": [
      "N02",
      "P03"
    ],
    "attackers": [],
    "condition": "让拍使队友更早攻击，同时剧院给其1盾；守门人自身仍慢1刻。"
  },
  {
    "id": "089",
    "name": "爆炉有医",
    "chapter": "C12",
    "members": [
      "F05",
      "B03"
    ],
    "attackers": [],
    "condition": "工人自伤后由医师后续治疗承接，维持多次4伤普攻；同刻医师若先疗满血，不能抵消之后才到的伤口。"
  },
  {
    "id": "090",
    "name": "裂炉织甲",
    "chapter": "C12",
    "members": [
      "F05",
      "E10"
    ],
    "attackers": [],
    "condition": "工人前置自伤扣血后回等量盾，保护下一轮；盾挡自伤的轮次不会再生盾。"
  },
  {
    "id": "091",
    "name": "裂口成诗",
    "chapter": "C12",
    "members": [
      "F08",
      "B04"
    ],
    "attackers": [],
    "condition": "织工把盾给诗人，延迟的1点伤害先由这面盾承受；诗人关闭主动技能留住剩余护盾。敌人随后打穿护盾并扣到诗人生命时，诗人为后排补盾。"
  },
  {
    "id": "092",
    "name": "火衣双生",
    "chapter": "C12",
    "members": [
      "F08",
      "B09"
    ],
    "attackers": [],
    "condition": "变形双生承接引线定时自伤并恢复1；常态只认敌傷，自伤被盾全挡也不会恢复。"
  },
  {
    "id": "093",
    "name": "炉口朝外",
    "chapter": "C12",
    "members": [
      "F05",
      "E18"
    ],
    "attackers": [],
    "condition": "前位工人普攻后的自伤改打敌前位，前两次获得净进攻；自己不再留治疗入口。"
  },
  {
    "id": "094",
    "name": "影债外送",
    "chapter": "C12",
    "members": [
      "N10",
      "E18"
    ],
    "attackers": [],
    "condition": "前置余像进攻抉择自伤2改打敌前位，同时保留前两刀+1；不会因未自扣血得到血井记录。"
  },
  {
    "id": "095",
    "name": "伤口补线",
    "chapter": "C12",
    "members": [
      "F05",
      "E09",
      "B03"
    ],
    "attackers": [],
    "condition": "工人扣血使下一疗+1，医师原疗1变2，开始填敌伤而不仅是自伤。"
  },
  {
    "id": "096",
    "name": "引线隔热",
    "chapter": "C12",
    "members": [
      "F08",
      "E07"
    ],
    "attackers": [],
    "condition": "引线盾接敌方2点技能/灼烧只耗1盾；自带1自伤仍耗1，不能把这部分伪称省盾。"
  },
  {
    "id": "097",
    "name": "隔夜血契",
    "chapter": "C13",
    "members": [
      "B01",
      "P06"
    ],
    "attackers": [],
    "condition": "自伤照付，治疗4延迟成6；目标要撑两刻，满血则可转成其他资源。"
  },
  {
    "id": "098",
    "name": "迟火长信",
    "chapter": "C13",
    "members": [
      "F01",
      "P06"
    ],
    "attackers": [],
    "condition": "火种每份2变3，定时点从2/4变4/6；给对方更多反应时间但总伤更高。"
  },
  {
    "id": "099",
    "name": "寄给空椅",
    "chapter": "C13",
    "members": [
      "F08",
      "P06"
    ],
    "attackers": [],
    "condition": "引线3盾变4并晚2刻，自伤代价仍按原计划2刻到；同层供盾先于伤害，可接住该次自伤。"
  },
  {
    "id": "100",
    "name": "延席不散",
    "chapter": "C13",
    "members": [
      "B02",
      "P06"
    ],
    "attackers": [],
    "condition": "关掉其他早期合格技能，让分席首次被寄，群疗2变3并延迟；可能错过急救。"
  },
  {
    "id": "101",
    "name": "井水来信",
    "chapter": "C13",
    "members": [
      "B07",
      "P06"
    ],
    "attackers": [],
    "condition": "看守作为第一合格技能，疗4变6延迟；若记录来自N10进攻分支，那个分支只有代价与计算规则，不抢信。"
  },
  {
    "id": "102",
    "name": "迟到卸压",
    "chapter": "C13",
    "members": [
      "F05",
      "P06"
    ],
    "attackers": [],
    "condition": "卸压的2盾和2伤都变3并晚2刻，双方落点仍分别解析；增强攻守但盾不即时救人。"
  },
  {
    "id": "103",
    "name": "守候契书",
    "chapter": "C13",
    "members": [
      "B01",
      "P06",
      "E14"
    ],
    "attackers": [],
    "condition": "借命治疗延迟成6，当前前位的接班人护盾帮助撑过空窗；场地供盾不抢技能首封信，目标必须仍活。"
  },
  {
    "id": "104",
    "name": "寄往身后",
    "chapter": "C13",
    "members": [
      "B10",
      "P06"
    ],
    "attackers": [],
    "condition": "若厨师亡语是首个合格技能，群疗3变4、晚2刻，死者仍能送到幸存友槽。"
  },
  {
    "id": "105",
    "name": "童火兽径",
    "chapter": "C14",
    "members": [
      "F01",
      "F09"
    ],
    "attackers": [],
    "condition": "引火童6刻普攻续火，使8刻或10刻前出手的逐火兽看到待发火而普攻+1；火过早烧完则失去收益。"
  },
  {
    "id": "106",
    "name": "长明趁热",
    "chapter": "C14",
    "members": [
      "F03",
      "E05"
    ],
    "attackers": [],
    "condition": "较慢且更长的灼烧窗口让行者首次行动有火可接；需要实际点火者，场地不凭空生火。"
  },
  {
    "id": "107",
    "name": "灰路添柴",
    "chapter": "C14",
    "members": [
      "F03",
      "F09"
    ],
    "attackers": [],
    "condition": "行者击杀为后继敌槽留火，逐火兽首次技能向另一个槽添柴时多1即时伤。"
  },
  {
    "id": "108",
    "name": "遗焰合流",
    "chapter": "C14",
    "members": [
      "F10",
      "F09"
    ],
    "attackers": [],
    "condition": "不熄者群烧后，逐火兽向其中一槽添柴，另外两槽火可贡献2即时伤；需三敌仍活。"
  },
  {
    "id": "109",
    "name": "织线添薪",
    "chapter": "C14",
    "members": [
      "F08",
      "F09"
    ],
    "attackers": [],
    "condition": "破盾火保持一个槽在燃烧，逐火兽朝别槽添柴打出额外伤害并扩大覆盖。"
  },
  {
    "id": "110",
    "name": "暖焰兽行",
    "chapter": "C14",
    "members": [
      "F06",
      "F09"
    ],
    "attackers": [],
    "condition": "修女6刻首次点火，后槽逐火兽随后攻击时得到+1，主动技能也能利用其他有火槽。"
  },
  {
    "id": "111",
    "name": "长夜聚薪",
    "chapter": "C14",
    "members": [
      "F09",
      "E05"
    ],
    "attackers": [],
    "condition": "逐火兽自己添的火持续更久，延长普攻加伤窗口；首刀是否能受益取决于技能后还有待发火。"
  },
  {
    "id": "112",
    "name": "烽火接站",
    "chapter": "C14",
    "members": [
      "F01",
      "E03",
      "F09"
    ],
    "attackers": [],
    "condition": "前槽火扩到中槽，逐火兽瞄后槽添柴得到两处火贡献；不会把同一槽的多包火算多个槽。"
  },
  {
    "id": "113",
    "name": "卸压成诗",
    "chapter": "C15",
    "members": [
      "F05",
      "B04"
    ],
    "attackers": [],
    "condition": "卸压盾给诗人用于开口，卸压敌伤先压同一敌人，诗人的技能更易推进。"
  },
  {
    "id": "114",
    "name": "裂炉开幕",
    "chapter": "C15",
    "members": [
      "F05",
      "E17"
    ],
    "attackers": [],
    "condition": "卸压伤敌、盾给己方，盾实际挡住攻击触发提前，使被护者更早补上伤害。"
  },
  {
    "id": "115",
    "name": "炉衣卸甲",
    "chapter": "C15",
    "members": [
      "F05",
      "E08"
    ],
    "attackers": [],
    "condition": "卸压2盾被吸收或消耗换下一刀+1，开战2伤已先压血，攻守两端接在同一击杀线。"
  },
  {
    "id": "116",
    "name": "归炉回声",
    "chapter": "C15",
    "members": [
      "F05",
      "N01",
      "N07"
    ],
    "attackers": [],
    "condition": "重放卸压补盾，招领员把已有盾转出并催队友，另一端2伤照常重放；回放不复制招领员基础。"
  },
  {
    "id": "117",
    "name": "史官记炉",
    "chapter": "C15",
    "members": [
      "F05",
      "N06"
    ],
    "attackers": [],
    "condition": "史官选择D只回放卸压伤害、不回放其盾，基础疗前位承接卸压原盾后的生命伤；需要前位真有伤。"
  },
  {
    "id": "118",
    "name": "送炉成信",
    "chapter": "C15",
    "members": [
      "F05",
      "P06",
      "E15"
    ],
    "attackers": [],
    "condition": "卸压友盾先按信变3，再依据角色相距获得赠礼，敌伤变3；双方距离不影响敌伤部分。"
  },
  {
    "id": "119",
    "name": "余波卸炉",
    "chapter": "C15",
    "members": [
      "F05",
      "E02"
    ],
    "attackers": [],
    "condition": "卸压实际伤敌引出后槽1伤，同时自己盾吸收自伤或敌伤；盾端也须真正使用。"
  },
  {
    "id": "120",
    "name": "炉前双拍",
    "chapter": "C15",
    "members": [
      "F05",
      "P03",
      "E12"
    ],
    "attackers": [],
    "condition": "卸压盾在轻甲下变1并催1刻，剧院追加1盾不再递归；敌伤先压血，受盾者更早攻击。"
  },
  {
    "id": "121",
    "name": "熔穿猎场",
    "chapter": "C16",
    "members": [
      "F07",
      "B06"
    ],
    "attackers": [],
    "condition": "穿盾2压实际生命比例，猎手后出手得到比例加伤；对方盾仍会挡猎手的普通伤害。"
  },
  {
    "id": "122",
    "name": "熔刃余烬",
    "chapter": "C16",
    "members": [
      "F07",
      "P01"
    ],
    "attackers": [],
    "condition": "穿透分量击杀1血厚盾者时，合法生命溢出可继续打下一人；普通被盾吸收部分不算溢出。"
  },
  {
    "id": "123",
    "name": "隔甲织衣",
    "chapter": "C16",
    "members": [
      "F07",
      "E19"
    ],
    "attackers": [],
    "condition": "熔穿击杀的有效生命溢出转自己护盾，让后续能承接攻击。"
  },
  {
    "id": "124",
    "name": "碎甲火路",
    "chapter": "C16",
    "members": [
      "F07",
      "F03"
    ],
    "attackers": [],
    "condition": "斗士穿盾先压血，行者后来普攻击杀留火；须穿透部分确实改变击杀时点。"
  },
  {
    "id": "125",
    "name": "熔刃墓铭",
    "chapter": "C16",
    "members": [
      "F07",
      "N09"
    ],
    "attackers": [],
    "condition": "斗士先压血，自己死后刻名按印刷3伤补刀；残盾仍能挡亡语，需核对不是空想斩杀。"
  },
  {
    "id": "126",
    "name": "静默熔穿",
    "chapter": "C16",
    "members": [
      "F07",
      "N05"
    ],
    "attackers": [],
    "condition": "压住敌人首次行动的自疗/供盾，斗士提前完成穿盾击杀；基础治疗不会被“静默”封掉。"
  },
  {
    "id": "127",
    "name": "穿心续火",
    "chapter": "C16",
    "members": [
      "F07",
      "F01"
    ],
    "attackers": [],
    "condition": "童火第一次普攻点燃敌方前位，逐次灼烧护盾；斗士随后穿过仍在的护盾扣到生命。两路伤害必须都实际发生。"
  },
  {
    "id": "128",
    "name": "熔刃迎新王",
    "chapter": "C16",
    "members": [
      "F07",
      "N03"
    ],
    "attackers": [],
    "condition": "斗士留下残血敌人后死亡，变形王加伤收割；若仍需相同攻击次数则不算有效配合。"
  },
  {
    "id": "129",
    "name": "双生催宴",
    "chapter": "C17",
    "members": [
      "B09",
      "B02",
      "N02",
      "E20"
    ],
    "attackers": [],
    "condition": "守门人提前双生，引出急行军自伤，变形基础恢复后使司仪积伤；常态双生不认自伤，初始有盾也可能挡住入口。"
  },
  {
    "id": "130",
    "name": "新王登极",
    "chapter": "C17",
    "members": [
      "N03",
      "E13"
    ],
    "attackers": [],
    "condition": "变形王因队友死提高普攻伤害，又被掌声催早出手，既增量也提前兑现。"
  },
  {
    "id": "131",
    "name": "炉卫借衣",
    "chapter": "C17",
    "members": [
      "F02",
      "F08"
    ],
    "attackers": [],
    "condition": "炉卫变形后失去自造盾，引线供盾支持首次消耗爆发；引线自伤会提前磨掉部分盾。"
  },
  {
    "id": "132",
    "name": "灰身长夜",
    "chapter": "C17",
    "members": [
      "F10",
      "E05"
    ],
    "attackers": [],
    "condition": "变形死亡集中2火，在慢火下每份3、间隔3，强化单点持续压力，牺牲群烧。"
  },
  {
    "id": "133",
    "name": "影甲先行",
    "chapter": "C17",
    "members": [
      "N10",
      "E12"
    ],
    "attackers": [],
    "condition": "选4盾分支，轻甲变3盾并催1刻，前两刀虽减伤但更早打；选进攻没有这条盾入口。"
  },
  {
    "id": "134",
    "name": "影刀炉灰",
    "chapter": "C17",
    "members": [
      "N10",
      "P01"
    ],
    "attackers": [],
    "condition": "进攻分支前两刀+1，溢出伤下一人；2自伤是获取前期爆发的代价。"
  },
  {
    "id": "135",
    "name": "血肤记忆",
    "chapter": "C17",
    "members": [
      "B09",
      "E09"
    ],
    "attackers": [],
    "condition": "变形双生实际受伤后的自疗1被记忆增至2，最多各自三次；致命伤仍救不回。"
  },
  {
    "id": "136",
    "name": "灰身即焚",
    "chapter": "C17",
    "members": [
      "F10",
      "E04"
    ],
    "attackers": [],
    "condition": "变形死亡灼烧2的两份合为即时4伤，舍弃常态群体即时2；更可能当场突破一个位置。"
  },
  {
    "id": "137",
    "name": "门前缝心",
    "chapter": "C18",
    "members": [
      "P05",
      "B03"
    ],
    "attackers": [],
    "condition": "前排被打过半血获得提前，医师缝合/普攻治疗让它活到被提前的那刀；先受致命伤则无门。"
  },
  {
    "id": "138",
    "name": "门后余温",
    "chapter": "C18",
    "members": [
      "P05",
      "F06"
    ],
    "attackers": [],
    "condition": "半血抢拍者通过修女灼烧治疗续命，利用速度回报先攻击；需要实际火源。"
  },
  {
    "id": "139",
    "name": "逆旅开席",
    "chapter": "C18",
    "members": [
      "P05",
      "B02"
    ],
    "attackers": [],
    "condition": "群疗保住多个已被提前的残血人，让他们继续输出；治疗回半血以上不刷新底板次数。"
  },
  {
    "id": "140",
    "name": "血井候拍",
    "chapter": "C18",
    "members": [
      "P05",
      "B07"
    ],
    "attackers": [],
    "condition": "自伤队友到半血提前，井记录其损失后治疗它，使自伤换来的速度能兑现。"
  },
  {
    "id": "141",
    "name": "归客候诊",
    "chapter": "C18",
    "members": [
      "P05",
      "N08"
    ],
    "attackers": [],
    "condition": "客人伤到半血提前到首次行动，开启缺席得盾再推迟2；速度抵消只为更早拿盾，不伪称净加速。"
  },
  {
    "id": "142",
    "name": "影债开门",
    "chapter": "C18",
    "members": [
      "P05",
      "N10"
    ],
    "attackers": [],
    "condition": "分4血余像进攻自伤2触发提前，前两刀加伤更早兑现；薄血也更容易被后槽技能点死。"
  },
  {
    "id": "143",
    "name": "末席催归",
    "chapter": "C18",
    "members": [
      "P05",
      "B10"
    ],
    "attackers": [],
    "condition": "厨师亡语群疗救已半血抢拍的活队友；其提前必须已成立且尚未攻击。"
  },
  {
    "id": "144",
    "name": "血契启门",
    "chapter": "C18",
    "members": [
      "P05",
      "B01"
    ],
    "attackers": [],
    "condition": "4血侍者自伤2触发提前，借命可选自己随后治回，获得速度与回血；护盾挡住自伤会关掉入口。"
  },
  {
    "id": "145",
    "name": "缺席候诊",
    "chapter": "C19",
    "members": [
      "N08",
      "B03"
    ],
    "attackers": [],
    "condition": "客人以推迟换3盾，医师在等待期恢复实际生命，让客人延后的刀仍能打出。"
  },
  {
    "id": "146",
    "name": "空椅听火",
    "chapter": "C19",
    "members": [
      "N08",
      "F01"
    ],
    "attackers": [],
    "condition": "客人盾撑住迟刀空窗，敌人定时火先扣血，客人后刀更容易收割；不能把延迟本身算伤害。"
  },
  {
    "id": "147",
    "name": "静坐暖焰",
    "chapter": "C19",
    "members": [
      "N08",
      "F06"
    ],
    "attackers": [],
    "condition": "缺席盾争到修女灼烧治疗窗口，再把生命和盾分层利用；敌大爆发可能仍穿过。"
  },
  {
    "id": "148",
    "name": "等一件衣",
    "chapter": "C19",
    "members": [
      "N08",
      "P06"
    ],
    "attackers": [],
    "condition": "缺席3盾作为首封合格信变4但延迟2，A推迟仍立即发生；要先扛过无盾空窗，收益才成立。"
  },
  {
    "id": "149",
    "name": "缺席卸甲",
    "chapter": "C19",
    "members": [
      "N08",
      "E08"
    ],
    "attackers": [],
    "condition": "主动放慢得3盾，后续吸伤累计2让延后那刀+1；需盾在攻击前实际消耗。"
  },
  {
    "id": "150",
    "name": "静幕缓冲",
    "chapter": "C19",
    "members": [
      "N08",
      "E17"
    ],
    "attackers": [],
    "condition": "缺席盾首次挡伤，场地催2抵消先前推迟；敌人伤害时机决定是否真的抢回速度。"
  },
  {
    "id": "151",
    "name": "轻衣候客",
    "chapter": "C19",
    "members": [
      "N08",
      "E12"
    ],
    "attackers": [],
    "condition": "缺席3盾变2盾且自己先推迟2，得盾触发的提前1随后抵消一部分，净推迟1；没有获得同刻额外攻击。"
  },
  {
    "id": "152",
    "name": "殉卫隔席",
    "chapter": "C19",
    "members": [
      "B05",
      "E15"
    ],
    "attackers": [],
    "condition": "卫士慢1给相隔两槽队友3+2盾，以自己的节奏换更大保护；距离不放大自己的延迟。"
  },
  {
    "id": "153",
    "name": "卫士收债",
    "chapter": "C20",
    "members": [
      "B05",
      "P02"
    ],
    "attackers": [],
    "condition": "卫士实际吃敌伤获下一刀+1，配本身4伤推进；自伤不重复记债。"
  },
  {
    "id": "154",
    "name": "双生留账",
    "chapter": "C20",
    "members": [
      "B09",
      "P02"
    ],
    "attackers": [],
    "condition": "双生吃敌伤记+1又恢复，下一刀同时享受存活和进攻收益；变形减伤害需另计。"
  },
  {
    "id": "155",
    "name": "诗人的欠条",
    "chapter": "C20",
    "members": [
      "B04",
      "P02"
    ],
    "attackers": [],
    "condition": "诗人敌伤同时给后排盾、给自己记债，既保人又反击；死后另有一份给当前前位。"
  },
  {
    "id": "156",
    "name": "裂炉还债",
    "chapter": "C20",
    "members": [
      "F05",
      "P02"
    ],
    "attackers": [],
    "condition": "工人承接前人死亡债，下一刀由4变5；自伤来源不是敌人，不造新的受伤债。"
  },
  {
    "id": "157",
    "name": "猎手讨账",
    "chapter": "C20",
    "members": [
      "B06",
      "P02"
    ],
    "attackers": [],
    "condition": "猎手的比例加伤与已记的债共同作用下一刀，需维持生命比例，不能把加成误当永久攻击。"
  },
  {
    "id": "158",
    "name": "新王偿还",
    "chapter": "C20",
    "members": [
      "N03",
      "P02"
    ],
    "attackers": [],
    "condition": "变形王因队友死提升后续伤害，并在自己是当前前位时接到额外一刀债。"
  },
  {
    "id": "159",
    "name": "灰路催账",
    "chapter": "C20",
    "members": [
      "F03",
      "P02"
    ],
    "attackers": [],
    "condition": "行者用附债普攻更早完成击杀并续火，债转成后续定时伤害入口。"
  },
  {
    "id": "160",
    "name": "葬宴结账",
    "chapter": "C20",
    "members": [
      "B10",
      "P02"
    ],
    "attackers": [],
    "condition": "厨师死亡治疗幸存者，底板同时给当前前位加一刀伤害；两个接收人可不同。"
  },
  {
    "id": "161",
    "name": "遗物添刃",
    "chapter": "C21",
    "members": [
      "N07",
      "E08"
    ],
    "attackers": [],
    "condition": "归还实际转出2盾，让招领员自己下一刀+1，接收者仍得盾并提前；源方没盾时只有保底催拍，不能额外加伤。"
  },
  {
    "id": "162",
    "name": "引线余拍",
    "chapter": "C21",
    "members": [
      "F08",
      "E17"
    ],
    "attackers": [],
    "condition": "引线盾第一次挡伤就催受盾者2刻，之后破盾还能点火；提前与破盾是不同事件。"
  },
  {
    "id": "163",
    "name": "影子旧衣",
    "chapter": "C21",
    "members": [
      "N10",
      "E08"
    ],
    "attackers": [],
    "condition": "防御分支4盾损失后换至多2下一刀伤害，可补前两刀减伤；必须确实消耗，不是拿盾就加。"
  },
  {
    "id": "164",
    "name": "炉壁换刀",
    "chapter": "C21",
    "members": [
      "F02",
      "E08"
    ],
    "attackers": [],
    "condition": "常态炉卫从灼烧得盾，盾被打掉换下刀加伤；不是变形消耗盾路线。"
  },
  {
    "id": "165",
    "name": "遗物诗锋",
    "chapter": "C21",
    "members": [
      "N07",
      "B04"
    ],
    "attackers": [],
    "condition": "招领员第一刀前归还盾给后出手诗人，诗人随后消耗打伤；需招领员早于诗人并已有盾。"
  },
  {
    "id": "166",
    "name": "旧衣出炉",
    "chapter": "C21",
    "members": [
      "N07",
      "F02"
    ],
    "attackers": [],
    "condition": "招领员把盾交给尚未首攻的变形炉卫，炉卫消耗成伤；需安排出手先后。"
  },
  {
    "id": "167",
    "name": "轻甲拾遗",
    "chapter": "C21",
    "members": [
      "N07",
      "E12"
    ],
    "attackers": [],
    "condition": "队友破盾给招领员2盾被减成1，但提前其行动，较早归还或普攻；归还给另一人也可能再催。"
  },
  {
    "id": "168",
    "name": "借壳卸甲",
    "chapter": "C21",
    "members": [
      "N04",
      "E08"
    ],
    "attackers": [],
    "condition": "借壳从队友转出盾，使源方累计失盾换下一刀加伤，自己接盾承伤；不同于借名者自己的破盾抢拍。"
  },
  {
    "id": "169",
    "name": "双医续脉",
    "chapter": "C22",
    "members": [
      "B03",
      "F06"
    ],
    "attackers": [],
    "condition": "医师和修女在不同时间治疗同一伤员，期间承受过生命伤害；不把满血空奶算接力。"
  },
  {
    "id": "170",
    "name": "自缝与医",
    "chapter": "C22",
    "members": [
      "B09",
      "B03"
    ],
    "attackers": [],
    "condition": "双生自疗缓冲第一下，医师后续再治，撑过持续攻击；医师当前前位选择要命中同人。"
  },
  {
    "id": "171",
    "name": "红契长诊",
    "chapter": "C22",
    "members": [
      "B01",
      "B03"
    ],
    "attackers": [],
    "condition": "借命补一次大伤，缝合或普攻治疗继续补同一人；首次借命全溢出则不属于实血接力。"
  },
  {
    "id": "172",
    "name": "井后暖流",
    "chapter": "C22",
    "members": [
      "B07",
      "F06"
    ],
    "attackers": [],
    "condition": "血井大疗后，修女在下一次伤口出现时续上，保住前排并让后排继续攻。"
  },
  {
    "id": "173",
    "name": "葬宴余温",
    "chapter": "C22",
    "members": [
      "B10",
      "F06"
    ],
    "attackers": [],
    "condition": "厨师死亡救伤员，修女后来用燃烧收益再救它；火源不可省略。"
  },
  {
    "id": "174",
    "name": "双生暖祷",
    "chapter": "C22",
    "members": [
      "B09",
      "F06"
    ],
    "attackers": [],
    "condition": "双生受伤自疗、修女后续疗它，把两个小恢复窗口接起来；致命伤无效。"
  },
  {
    "id": "175",
    "name": "旧书新血",
    "chapter": "C22",
    "members": [
      "N06",
      "B03"
    ],
    "attackers": [],
    "condition": "回放缝合的治疗后，医师后续普攻治疗同一伤员；史官基础也有独立次数上限。"
  },
  {
    "id": "176",
    "name": "承诺再缝",
    "chapter": "C22",
    "members": [
      "B08",
      "B03"
    ],
    "attackers": [],
    "condition": "医师缝合指后槽继承人，首段承诺转给前位且+2，第二段回到后槽；前位后续再受医师普攻治疗形成接力。"
  },
  {
    "id": "177",
    "name": "后院火炉",
    "chapter": "C23",
    "members": [
      "F01",
      "F02"
    ],
    "attackers": [],
    "condition": "火种点后槽，烧入生命即给前排炉卫盾，不需先打穿敌前位。"
  },
  {
    "id": "178",
    "name": "焚后余波",
    "chapter": "C23",
    "members": [
      "F04",
      "E02"
    ],
    "attackers": [],
    "condition": "烧毁日程打中槽并扣血，余波打后槽1，原中槽还会被推迟；目标名公开但位置仍需猜。"
  },
  {
    "id": "179",
    "name": "隔山逐火",
    "chapter": "C23",
    "members": [
      "F09",
      "E03"
    ],
    "attackers": [],
    "condition": "添柴瞄中槽，扩散给后槽，更多槽有火延长逐火兽加伤机会；不开技能则无自启动。"
  },
  {
    "id": "180",
    "name": "后院余波",
    "chapter": "C23",
    "members": [
      "B06",
      "E02"
    ],
    "attackers": [],
    "condition": "猎手点中槽2实伤，再碰后槽1；若原伤被盾全挡无余波。"
  },
  {
    "id": "181",
    "name": "一火两灯",
    "chapter": "C23",
    "members": [
      "F01",
      "E03"
    ],
    "attackers": [],
    "condition": "火种瞄中槽2火，后槽也有1火，可攻击两处低血部署；追加不继续扩散。"
  },
  {
    "id": "182",
    "name": "暗箭烧信",
    "chapter": "C23",
    "members": [
      "F04",
      "B06"
    ],
    "attackers": [],
    "condition": "焚信开战先伤并推迟后槽，猎手随后点同槽收割，取消其晚到的首刀。"
  },
  {
    "id": "183",
    "name": "急火暗箭",
    "chapter": "C23",
    "members": [
      "F01",
      "B06",
      "E04"
    ],
    "attackers": [],
    "condition": "火种立即4伤，猎手之后补2；需要后槽目标未在首段就死，且提前击杀确实有价值。"
  },
  {
    "id": "184",
    "name": "遥伤接烬",
    "chapter": "C23",
    "members": [
      "B06",
      "P01"
    ],
    "attackers": [],
    "condition": "猎手技能先压后槽血，随后普攻溢出接近收割；只有该后槽已是下一活敌人才会被余烬击中，不能越过仍活中槽。"
  },
  {
    "id": "185",
    "name": "火衣诗刀",
    "chapter": "C24",
    "members": [
      "F08",
      "B04"
    ],
    "attackers": [],
    "condition": "引线供3盾给诗人，首次行动消耗剩盾打伤；2刻自伤及敌攻可能先磨盾。"
  },
  {
    "id": "186",
    "name": "卫衣诗锋",
    "chapter": "C24",
    "members": [
      "B05",
      "B04"
    ],
    "attackers": [],
    "condition": "卫士给诗人3盾，诗人首次行动变3伤，卫士为此慢1刻。"
  },
  {
    "id": "187",
    "name": "灯下诗锋",
    "chapter": "C24",
    "members": [
      "B04",
      "E14"
    ],
    "attackers": [],
    "condition": "诗人无盾开局接战得到2盾，首次行动前若仍存就消耗打2；提前被打空则失败。"
  },
  {
    "id": "188",
    "name": "灯亮出炉",
    "chapter": "C24",
    "members": [
      "F02",
      "E14"
    ],
    "attackers": [],
    "condition": "变形炉卫接战得2盾，首攻前剩盾转伤；常态不能使用消耗技能。"
  },
  {
    "id": "189",
    "name": "卸甲诗锤",
    "chapter": "C24",
    "members": [
      "B04",
      "E08"
    ],
    "attackers": [],
    "condition": "诗人消耗3盾打3伤，同时累计失盾给紧接的一刀+1；不是破盾触发。"
  },
  {
    "id": "190",
    "name": "双炉卸甲",
    "chapter": "C24",
    "members": [
      "F02",
      "E08"
    ],
    "attackers": [],
    "condition": "变形炉卫消耗4盾打4，再为下一普攻存+2，代价是防护全部消失。"
  },
  {
    "id": "191",
    "name": "引线余音",
    "chapter": "C24",
    "members": [
      "F08",
      "E16",
      "B04"
    ],
    "attackers": [],
    "condition": "引线盾分2与1两段到账，诗人晚些行动可消耗留存部分；分盾期间吸伤可能优于一次堆盾，也可能亏。"
  },
  {
    "id": "192",
    "name": "满杯诗锋",
    "chapter": "C24",
    "members": [
      "B01",
      "E11",
      "B04"
    ],
    "attackers": [],
    "condition": "借命对满血诗人造2盾，诗人首攻前消耗打2；不是把侍者自己的盾送过去。"
  },
  {
    "id": "193",
    "name": "一火三用",
    "chapter": "C25",
    "members": [
      "F01",
      "F06",
      "B02"
    ],
    "attackers": [],
    "condition": "点火→烧伤使修女治疗非司仪伤员→司仪积伤并命中，三个来源连续贡献。"
  },
  {
    "id": "194",
    "name": "裂炉成宴",
    "chapter": "C25",
    "members": [
      "F05",
      "B03",
      "B02"
    ],
    "attackers": [],
    "condition": "工人实际自伤→医师治疗它→司仪积伤后攻击；需医师治疗发生在自伤之后。"
  },
  {
    "id": "195",
    "name": "火衣留名",
    "chapter": "C25",
    "members": [
      "F08",
      "N04",
      "N07"
    ],
    "attackers": [],
    "condition": "织工给借名者盾→破盾令借名者抢拍并给招领员盾→招领员再送出盾催借名者，形成真实回流。"
  },
  {
    "id": "196",
    "name": "骨灰温床",
    "chapter": "C25",
    "members": [
      "F10",
      "F06",
      "B09"
    ],
    "attackers": [],
    "condition": "不熄者群火→修女救双生→双生自疗补另一次伤口，确实多活到一刀；第三环需反事实存活核对。"
  },
  {
    "id": "197",
    "name": "烧信催猎",
    "chapter": "C25",
    "members": [
      "F04",
      "N02",
      "B06"
    ],
    "attackers": [],
    "condition": "焚信压敌后槽时间与血线→守门人催猎手→猎手在对方行动前技能击杀，必须三次贡献都影响结果。"
  },
  {
    "id": "198",
    "name": "改稿回宴",
    "chapter": "C25",
    "members": [
      "N10",
      "B07",
      "B02"
    ],
    "attackers": [],
    "condition": "余像进攻自伤入井→看守治疗余像→司仪因此加伤；若余像已被补满，链条断。"
  },
  {
    "id": "199",
    "name": "墓宴复述",
    "chapter": "C25",
    "members": [
      "B10",
      "N01",
      "N06"
    ],
    "attackers": [],
    "condition": "见证记录厨师亡语群疗→回放再疗→史官基础额外疗当前前位1，所有治疗须有实际伤口。"
  },
  {
    "id": "200",
    "name": "红契归宴",
    "chapter": "C25",
    "members": [
      "B01",
      "B08",
      "B02"
    ],
    "attackers": [],
    "condition": "侍者自伤并治疗后排继承人→承诺改给前位侍者且+2→司仪因实际治疗积伤，盾挡自伤时可能无有效治疗。"
  },
  {
    "id": "201",
    "name": "双炉并刃",
    "chapter": "C26",
    "members": [
      "B05",
      "F05",
      "N02"
    ],
    "attackers": [
      "B05",
      "F05"
    ],
    "condition": "卫士前位、爆炉工中位、守门人后位；守门人开战让爆炉工提前2刻，两名近战都在第8刻普攻，守门人贡献有效加速。"
  },
  {
    "id": "202",
    "name": "卫证交锋",
    "chapter": "C27",
    "members": [
      "B05",
      "N01"
    ],
    "attackers": [
      "B05",
      "N01"
    ],
    "condition": "卫士放前位、关闭开战技能；远程见证不受站位影响。两人首刀同在第8刻，分别贡献近战与远程攻击。"
  },
  {
    "id": "203",
    "name": "双名齐射",
    "chapter": "C28",
    "members": [
      "B02",
      "N01"
    ],
    "attackers": [
      "B02",
      "N01"
    ],
    "condition": "两名远程首刀都在第8刻，不依赖技能开启；同刻普攻后按齐射规则治疗生命比例最低的队友。"
  },
  {
    "id": "204",
    "name": "三席共鸣",
    "chapter": "C29",
    "members": [
      "B05",
      "B02",
      "N01"
    ],
    "attackers": [
      "B05",
      "B02",
      "N01"
    ],
    "condition": "卫士放前位并关闭开战技能，两名远程同刻出手；三人首刀均在第8刻，触发三重奏、两次交叉掩护及一次齐射续援。"
  }
];
