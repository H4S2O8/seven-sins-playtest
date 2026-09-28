import type { Arena, Card, Gear, Plan, Signal, Unit } from "./types.js";
export const INTENT_RULESET = "intent-v4-single-field";
export const CARDS: Card[] = [
  {
    id: "WR1",
    name: "小红帽",
    grade: "S",
    mark: "aim",
    targets: ["enemy"],
    modes: false,
    basic: "shield",
    text: "付出自身1力量，使指定敌位失去3力量。",
    uses: ["强位保住领先并压另一线", "弱位让线，将削弱投向可争取的另一线"],
  },
  {
    id: "WR2",
    name: "狂战士",
    grade: "S",
    mark: "aim",
    targets: ["other"],
    modes: false,
    basic: "shield",
    text: "向指定队友转移2力量，队友额外获得2力量。",
    uses: ["强位分出余力", "牺牲弱位集中突破"],
  },
  {
    id: "WR3",
    name: "清算者",
    grade: "S",
    mark: "reinforce",
    targets: [],
    modes: false,
    text: "从另外两名队友各转移2力量给自己，第一笔转移额外获得1力量。",
    uses: ["集中争取关键线", "低数人物借两条富余线变成第二赢线"],
  },
  {
    id: "GR1",
    name: "豪商",
    grade: "S",
    mark: "aim",
    targets: ["other"],
    modes: false,
    basic: "reserve",
    text: "从指定队友转移3力量给自己，额外获得1力量。",
    uses: ["从放弃的位置回收资源", "从强位余量借力补短板"],
  },
  {
    id: "GR2",
    name: "赎罪券商",
    grade: "S",
    mark: "reinforce",
    targets: [],
    modes: false,
    basic: "reserve",
    text: "分别向另外两位转移1力量，两位各额外获得1力量。",
    uses: ["强位承担支援成本", "牺牲低数换两路进攻"],
  },
  {
    id: "GR3",
    name: "收藏家",
    grade: "S",
    mark: "reinforce",
    targets: [],
    modes: false,
    text: "从另外两名队友各转移1力量给自己，第一笔转移额外获得1力量。",
    uses: ["小额筹集保住两侧优势", "把不够赢的分散力量集中"],
  },
  {
    id: "GL1",
    name: "放血师",
    grade: "S",
    mark: "aim",
    targets: ["enemy"],
    modes: false,
    text: "从指定敌位吸取至多2力量，自己收到实际削减量；格挡掉的部分不能吸取。",
    uses: ["削主力并自保", "从较易穿透的位置吸取力量"],
  },
  {
    id: "GL2",
    name: "饕餮",
    grade: "S",
    mark: "aim",
    targets: ["other"],
    modes: false,
    text: "按战斗开始时的力量，将自己与指定队友差值的一半从高位转给低位，向下取整。",
    uses: ["把强位富余分给弱位", "让低数技能携带者借邻队主力起势"],
  },
  {
    id: "GL3",
    name: "食腐鸦",
    grade: "S",
    mark: "aim",
    targets: ["other"],
    modes: false,
    text: "主阶段从自己转出2力量，收尾交给指定队友，另加1点强化。",
    uses: ["避开只记录主阶段的干扰", "把弱位变成末段供能点"],
  },
  {
    id: "EN1",
    name: "密探",
    grade: "S",
    mark: "aim",
    targets: ["enemy"],
    modes: false,
    basic: "shield",
    text: "自身付出1力量；指定敌位收到的第一笔增益被夺走至多3点，交给自己。",
    uses: ["从敌方主力强化中获利", "锁定其辅助收款位阻止输送"],
  },
  {
    id: "EN2",
    name: "镜中人",
    grade: "S",
    mark: "flip",
    targets: [],
    modes: true,
    basic: "relay",
    text: "守面：自身第一笔敌方减力减半；攻面：自身获得3力量，随后付出1力量。",
    uses: ["用守面保护关键线", "确认威胁转移后用攻面补差"],
  },
  {
    id: "EN3",
    name: "扒手",
    grade: "S",
    mark: "aim",
    targets: ["enemy"],
    modes: false,
    text: "自身付出1力量；指定敌位第一笔增益最多削去3点，不转给自己。",
    uses: ["阻断主力供能", "压住原本差一点就赢的辅助位"],
  },
  {
    id: "SL1",
    name: "冬眠熊",
    grade: "S",
    mark: "reinforce",
    targets: [],
    modes: false,
    basic: "reserve",
    text: "主阶段付出2力量，收尾时自身获得4力量。",
    uses: ["延迟强化避开主阶段的记录", "在蓄能或代价装备支持下提升效率"],
  },
  {
    id: "SL2",
    name: "沉眠巨像",
    grade: "S",
    mark: "flip",
    targets: [],
    modes: true,
    text: "守面：自身第一笔敌方减力最多减少3；攻面：从两名队友各转移1力量，每笔额外获得1力量。",
    uses: ["守住已足够强的原数", "用攻面把弱数变成主力"],
  },
  {
    id: "SL3",
    name: "隐修士",
    grade: "C1",
    mark: "aim",
    targets: ["other"],
    modes: false,
    basic: "shield",
    text: "自身付出1力量；自己收到的首笔主阶段增益和首笔敌方减力，各转移至多4点给指定队友。两类分别计次。",
    uses: ["把强化经自己送往另一赢线", "把来袭削弱送往防护位或牺牲位"],
    mastery: "预测增益先后、分流对象与真正到账量。",
  },
  {
    id: "PR1",
    name: "孔雀",
    grade: "C1",
    mark: "aim",
    targets: ["enemy"],
    modes: false,
    basic: "shield",
    text: "自身付出1力量；记录指定敌位主阶段实际获得的增益，收尾削减它至多4点。",
    uses: ["标记高数强化主力", "标记低数接收器破坏翻盘"],
    mastery: "区分计划增益、被格挡增益和真实到账增益。",
  },
  {
    id: "PR2",
    name: "无瑕刺客",
    grade: "C1",
    mark: "aim",
    targets: ["other"],
    modes: false,
    text: "自身付出1力量；主阶段落到自己或指定队友的增益交换收款位置，总计最多6点。同一笔只交换一次。",
    uses: [
      "自己吸引供能，交给低数主力",
      "将对队友的强化收到自己，避开原接收位的截流",
    ],
    mastery: "选择供能目标并核算分流后的双线余量。",
  },
  {
    id: "PR3",
    name: "僭王",
    grade: "C3",
    mark: "choice",
    targets: ["other", "enemy"],
    modes: true,
    basic: "relay",
    text: "我即尺度：自身付出1；指定队友前两笔主阶段增益各分1给自己。收尾选择先朝贡后册封，或先册封后朝贡。朝贡：以自己当前力量为尺度，指定队友与敌位高于尺度的部分各交至多3，实际取得量归自己，友方交代价、敌方受削弱。册封：自己支付高于队友的差额一半，最多3，按实际支付量强化队友。每步骤开始冻结尺度，两步骤之间重新计算，各只一次。",
    uses: [
      "低数王索取强者贡品后培养另一赢线",
      "高数王先让利压低尺度再向敌位追贡",
    ],
    mastery:
      "操纵参照点、双对象同时计税、朝贡与册封顺序、实际支付和防护共同改变力量分布。目标C3，待验证。",
  },
  {
    id: "LU1",
    name: "痴情骑士",
    grade: "C1",
    mark: "aim",
    targets: ["other", "enemy"],
    modes: false,
    basic: "shield",
    text: "自身付出1力量；替指定队友承受首笔主阶段敌方减力。记录自己主阶段实际承受的敌方减力，收尾向指定敌位反击，最多4点。",
    uses: ["强位保护队友并跨线反击", "低数牺牲位替主力承伤，利用实际损失索债"],
    mastery: "友方技能代价不算敌方伤害，选错受压位会空转。",
  },
  {
    id: "LU2",
    name: "牵线人",
    grade: "C2",
    mark: "aim",
    targets: ["ally", "other"],
    modes: true,
    text: "建立单向契约：第一目标每笔主阶段增益（模式0）或敌方减力（模式1）的一半转移给第二目标，总计最多4；收尾第一目标获得实际转移量的一半。两目标必须不同。",
    uses: ["让富余强化流向短板", "将主力损失转给可放弃位置"],
    mastery: "选择符号、流向及容量；改变目标会同时改变保护和补偿的价值。",
  },
  {
    id: "LU3",
    name: "塞壬",
    grade: "C2",
    mark: "aim",
    targets: ["enemy", "other"],
    modes: false,
    basic: "relay",
    text: "自身付出2力量；指定敌位首笔主阶段增益减少至多3，记录实际夺得量；收尾把这笔量加1赠给指定队友，无夺得则无赠与。",
    uses: ["阻断敌方主力并补己方弱线", "压住敌方接收器而支援己方主力"],
    mastery: "选择敌方付款人和己方收款人，避开其延迟或蓄能。",
  },
  {
    id: "WR4",
    name: "攻城锤手",
    grade: "C3",
    mark: "choice",
    targets: ["other", "enemy"],
    modes: true,
    text: "复仇法庭：向指定队友转移2力量。记录自己和该队友主阶段实际受到的敌方削弱，按来源分账，总计最多6。收尾选择向指定敌位集中索债，或向原来源逐一追责；实际讨回量每2点恢复自己1，最多3；被格挡的欠账每2点反噬自己1。派生复仇不再次记账。",
    uses: ["强位保护第二赢线形成复仇威慑", "低数让线者借承伤跨线处刑"],
    mastery:
      "按攻击来源建立多本账，决定集中处刑或逐个追责；防护、改道、实际回收及反噬会改变路线价值。目标C3，待验证。",
  },
  {
    id: "GR4",
    name: "金库守卫",
    grade: "C3",
    mark: "choice",
    targets: ["ally", "other"],
    modes: true,
    basic: "reserve",
    text: "永续债权：自身支付2点启动费用，为两个不同友位各创造2点贷款增益（放款不属于力量搬运）。记录两者主阶段实际增益，各最多8；收尾各收取记录一半的实际代价，最多4。收租：本金加1归自己；再贷：本金给第二目标，本金一半分红给第一目标。无实际本金就无利息或分红；新款不再记账。",
    uses: ["低数债权人用收租集中起势", "高数担保人用再贷培养第二赢线"],
    mastery:
      "贷款、外来到账、实际追债、折价、分红分流和双债务人排序共同构成资金循环。目标C3，待验证。",
  },
  {
    id: "GL4",
    name: "噬铁软泥",
    grade: "C2",
    mark: "aim",
    targets: ["other"],
    modes: false,
    text: "自身付出1力量；记录己方主阶段被格挡的敌方减力、被丢弃的增益，以及其他友方技能实际支付的代价，总计最多4。收尾一半给自己，其余给指定队友。",
    uses: ["回收防护产生的余量", "把队友支援或抽取的实际成本转为另一线供能"],
    mastery: "区分真正被阻止、只是改道和主动代价；不能重复回收。",
  },
  {
    id: "GL5",
    name: "大野狼",
    grade: "C3",
    mark: "choice",
    targets: ["other", "enemy"],
    modes: true,
    basic: "shield",
    text: "三道饕宴：向指定队友转移2力量；吞下该队友首笔主阶段增益至多3为甜食，吞下指定敌位首笔主阶段受到的敌方削弱至多3为苦食。消化：自身获得总食量，双食另加2，苦食一半给队友；反刍：总食量削弱指定敌位，双食另给队友2。只吃一种则自身再付出1。吞食暂时阻止原效果，派生事件不再进食。",
    uses: ["吃强位富余强化给弱位狼供能", "暂时救敌以重组一次更集中的收尾攻击"],
    mastery:
      "同时管理增益和削弱两种食物、牺牲即时效果、目标防护与消化不良，计算不同出餐路线。目标C3，待验证。",
  },
  {
    id: "EN4",
    name: "影子",
    grade: "C3",
    mark: "choice",
    targets: ["other", "enemy"],
    modes: true,
    text: "篡我之镜：自身付出1；分别记录指定队友与指定敌人的主阶段技能增益轨迹，每本最多6。取代：按左右镜像在己方逐笔重演敌方轨迹，随后削弱指定敌位成功复制量的一半；歪曲：将队友轨迹最大一笔化为指定敌位减力，其他笔给自己，同大取先。被选轨迹每多涉及一个原目标，自身付出1；装备衍生、复制和收尾事件不录入。",
    uses: ["弱位借敌方支援复制力量分布", "将己方辅助输出结构歪曲为跨线进攻"],
    mastery:
      "分别判断来源、原轨迹、实际到账、分笔边界与镜像落点；模式选择还决定身份撕裂代价。目标C3，待验证。",
  },
  {
    id: "SL4",
    name: "守夜人",
    grade: "C3",
    mark: "choice",
    targets: ["ally", "other"],
    modes: true,
    basic: "reserve",
    text: "明日之王：自身付出1；暂存第一目标前两笔主阶段增益总计至多5，及首笔敌方削弱至多4。先还债：第一目标先偿还削弱，再逐笔把增益给第二目标，每实际还债2点补偿第一目标1，最多2。先享受：先给第一目标兑现增益，再由第二目标偿还削弱，每实际到账一笔补偿第二目标1，最多2。债务保留敌方来源，延期事件不能再次延期。",
    uses: [
      "强位先还债后把收益交给第二赢线",
      "弱位享受增益并由防护位或牺牲位承担债务",
    ],
    mastery:
      "双队列、部分暂存、先后次序、转移债务、来源防护与按实际值补偿共同决定结果。目标C3，待验证。",
  },
  {
    id: "LU4",
    name: "交际花",
    grade: "C3",
    mark: "choice",
    targets: ["other", "enemy"],
    modes: true,
    basic: "relay",
    text: "众心归我：自身付出2；暂存指定敌位首笔主阶段增益至多3为礼物，暂存指定队友首笔敌方削弱至多3为伤债。独占：礼物给自己、伤债给敌位，实际礼物超出实还伤债的部分至多2安抚队友，伤债更多则自己付出差额一半。移情：礼物给队友、自己还伤债，以实际还债加队友实际收礼一半削弱指定敌位，最多5；反击被真正格挡时队友付出格挡量一半。派生事件不再入账。",
    uses: [
      "自己作防护中心保护队友并挑动敌位",
      "牺牲自己承担伤债，以送给队友的礼物发动跨线反击",
    ],
    mastery:
      "三角关系中收礼、受伤、反击与安抚互相影响；选择受益者、偿债者和公开对象而隐藏关系模式。目标C3，待验证。",
  },
  {
    id: "LU5",
    name: "双子",
    grade: "C2",
    mark: "choice",
    targets: ["ally", "other"],
    modes: true,
    text: "自身付出1力量；链接两名不同友方，每名首笔主阶段增益抽取一半入共同账本，总容量4，双方敌方减力分别记录至多3。收尾模式0优先补偿受损更多者，余款给另一位；模式1平分账本，再将较多的损失记录化为自身强化，最多3。",
    uses: ["把分散强化转成受压位的动态保险", "在可放弃线吸收攻击时培养第三位"],
    mastery:
      "双方首笔的时序、共同容量、损失比较、平局分账和第三位收益相互制约；不能靠单一固定连招掌握。",
  },
];
export const GEARS: Gear[] = [
  {
    id: "G01",
    name: "增幅线圈",
    text: "自己技能首笔正向增益+2，同时自己额外付出1。",
    uses: ["放大单点支援", "强化吸取后的恢复"],
  },
  {
    id: "G02",
    name: "分流阀",
    text: "自己收到的首笔主阶段增益，一半转给原数最低的其他队友。",
    uses: ["强位分出富余", "将被汇聚的力量重新分线"],
  },
  {
    id: "G03",
    name: "集束冠",
    text: "其他队友主阶段每笔增益转移1给自己，每手最多4。",
    uses: ["把群体技能集中", "把低数装备位变成收款核心"],
  },
  {
    id: "G04",
    name: "缓冲甲",
    text: "敌方减力减半，向下取整，不减免己方代价。",
    uses: ["保护原数主力", "保护依赖强化的小数位"],
  },
  {
    id: "G05",
    name: "一次护幕",
    text: "第一笔敌方减力最多格挡3点。",
    uses: ["防单次重击", "替护送者承接一次攻击"],
  },
  {
    id: "G06",
    name: "泄压管",
    text: "第一笔主阶段敌方减力的一半转给原数最高的其他队友。",
    uses: ["把脆弱位压力分给富余位", "利用队友受损记录发动补偿"],
  },
  {
    id: "G07",
    name: "回收刃",
    text: "自身技能实际削减敌方力量时，恢复一半给自己，每手最多3。",
    uses: ["让弱位削弱也能自救", "延迟反击时补回主力"],
  },
  {
    id: "G08",
    name: "回声针",
    text: "自身技能的主阶段增益实际到账后，另给原数最低的其他队友1点，最多3次。",
    uses: ["群体支援产生额外弱线收益", "单点强援顺带补另一线"],
  },
  {
    id: "G09",
    name: "蓄能器",
    text: "暂存收到的主阶段增益至多4，收尾释放并另加暂存量一半。",
    uses: ["接自身强化", "接队友支援避开主阶段截取"],
  },
  {
    id: "G10",
    name: "反震片",
    text: "首次实际受到敌方减力后，反还2点给效果来源位置。",
    uses: ["保护关键位形成威慑", "护送他人后反击攻击者"],
  },
  {
    id: "G11",
    name: "折射棱镜",
    text: "主阶段收到的增益取一半，分给另外两位；奇数余量给较左者。每手最多分出6点，同一笔只经过本装备一次。",
    uses: ["把集中强化拆成两线支援", "用分笔触发不同接收装备或接力能力"],
  },
  {
    id: "G12",
    name: "聚焦镜",
    text: "自己技能第一笔正向增益+3，之后每笔正向增益-1，最低0。",
    uses: ["强化单点输出", "改变群体支援的重心"],
  },
  {
    id: "G13",
    name: "侧接导线",
    text: "主阶段每笔收到的增益转1点给左邻，最左绕回最右；每手最多3点，同一笔只经过本装备一次。",
    uses: ["改变强化最终落点", "将弱位作为通向蓄能或主力的接线点"],
  },
  {
    id: "G14",
    name: "逆相片",
    text: "首笔敌方减力中最多2点转为自身增益。",
    uses: ["受压位自救", "配合护送接入攻击并转化"],
  },
  {
    id: "G15",
    name: "延时匣",
    text: "自己技能的主阶段增益延迟至收尾，每笔额外+1，最多补2次。",
    uses: ["躲避主阶段截取", "用延迟支援打破记录顺序"],
  },
  {
    id: "G16",
    name: "折价印",
    text: "自己技能造成的己方代价减少1，每手最多减2。",
    uses: ["降低自我牺牲成本", "保住被抽取资源的队友"],
  },
  {
    id: "G17",
    name: "超载环",
    text: "自己技能前两笔主阶段正向增益各+2，每次自己额外付出1。",
    uses: ["扩大群体输出", "让单点供能越过关键差值"],
  },
  {
    id: "G18",
    name: "引雷链",
    text: "原数最低的其他队友首笔主阶段敌方减力转给自己，并减去1。",
    uses: ["强位保护短板", "牺牲位吸收攻击触发记录或反震"],
  },
  {
    id: "G19",
    name: "摊伤网",
    text: "自身首笔主阶段敌方减力，分一半给原数最低的其他队友。",
    uses: ["主力保留更多力量", "为其他位置的受损补偿提供输入"],
  },
  {
    id: "G20",
    name: "缓释层",
    text: "自身首笔主阶段敌方减力延后至收尾，原额偿还。",
    uses: ["避开主阶段受损复制", "避免伤害在主阶段被别处转化后重复利用"],
  },
  {
    id: "G21",
    name: "余波罐",
    text: "己方主阶段真正格挡的敌方减力、丢弃的增益或技能实际支付的代价，为自己积累至多2点收尾强化。",
    uses: ["防守队通过格挡反哺输出", "支援队回收实际代价补第二赢线"],
  },
  {
    id: "G22",
    name: "献礼结",
    text: "自身主阶段增益每笔转1给原数最高的其他队友，最多3次。",
    uses: ["低数辅助集中喂主力", "让强位自强同时支援第二强位"],
  },
  {
    id: "G23",
    name: "整流栅",
    text: "自身技能给原数小于自己的队友的正向增益+1，其他正向增益-1，最低0。",
    uses: ["大数人物带起低数队友", "用固定数字关系决定资源该由谁输出"],
  },
  {
    id: "G24",
    name: "均压斗篷",
    text: "主阶段若自身力量高于己方平均，收到的增益全部转给当前最低的其他队友；否则保留并额外+1，补益每手最多2。",
    uses: ["主力溢出供给短板", "低位先收增益，再作为转发点"],
  },
];
export const FIELDS: Arena[] = [
  {
    id: "F1",
    name: "迁流潮汐",
    text: "转移力量时，转出多少，接收方就收到两倍。",
    uses: ["相同支出养起更弱的队友", "同样的吸取或截取换取双倍收入"],
  },
  {
    id: "F2",
    name: "援助扩散",
    text: "每当收到队友的强化，右邻也获得同样一份。",
    uses: ["集中支援顺带养第三路", "让转运节点成为新的支援入口"],
  },
  {
    id: "F3",
    name: "屏障回响",
    text: "挡下多少敌方削弱，就给左邻多少力量。",
    uses: ["主力防护同时养相邻队友", "让承伤位通过格挡向另一线供能"],
  },
  {
    id: "F4",
    name: "代价熔炉",
    text: "技能实际付出的力量，全部加到它下一笔强化上。",
    uses: ["把自损成本变成更强支援", "从队友抽取后将代价集中到关键一笔"],
  },
  {
    id: "F5",
    name: "缓流闸门",
    text: "主阶段每笔强化只先到账1点，其余留到收尾。",
    uses: ["大笔强化绕过主阶段截流", "分成小笔以保留即时接力和复制输入"],
  },
  {
    id: "F6",
    name: "余温护场",
    text: "每次获得己方强化，同时获得等量护场，抵挡之后的敌方削弱。",
    uses: ["自强同时抵挡攻击", "支援弱位时一并建立防护"],
  },
  {
    id: "F7",
    name: "弱者收礼",
    text: "己方强化总是流向当前力量最低的友军。",
    uses: ["低数接收大笔自强", "先付出代价，抢走原本属于别人的强化"],
  },
  {
    id: "F8",
    name: "逆向祝福",
    text: "己方强化改为削弱相同位置的敌人。",
    uses: ["支援牌变成跨线攻击", "给自己强化，改为突破自己的对位"],
  },
];
export const SINS = {
  WR: { name: "暴怒", desire: "伤害必须升级为报复" },
  GR: { name: "贪婪", desire: "每一笔资源都应成为我的资产" },
  GL: { name: "暴食", desire: "吞下效果，消化为另一种结果" },
  EN: { name: "嫉妒", desire: "别人拥有的成功应该属于我" },
  SL: { name: "怠惰", desire: "现在的代价交给以后或别人" },
  PR: { name: "傲慢", desire: "自己是尺度，别人必须服从" },
  LU: { name: "色欲", desire: "以诱惑与依附控制关系" },
};
/** Design hypotheses for player-facing reading, not extra numeric bonuses or measured win rates. */
export const FIELD_FITS: Record<
  string,
  { numbers: string; roles: string; alternative: string; watch: string }
> = {
  F1: {
    numbers: "高低混合有明确供体；三低可尝试借敌方资源",
    roles: "搬运、吸取、截取、增益改道",
    alternative: "三高有余量支持多次转运，而不是只能把一个低数扶起来",
    watch: "翻倍也可能放大敌方截取；只计算实际转出量",
  },
  F2: {
    numbers: "三高或多中高更容易维持三条有用的接收线",
    roles: "支援、分流、转运",
    alternative: "三低需要组织多个接收点，让扩散跨过原数差距",
    watch: "自己发给自己的强化不扩散，顺序和最终接收位置重要",
  },
  F3: {
    numbers: "三高可把防护收益用于巩固邻线；高低混合也可让专职防护位养弱位",
    roles: "格挡、护送、敌方削弱改道",
    alternative: "低数承伤者也能在格挡后支援高数主力",
    watch: "对手不攻击、改指向或使用付出代价，就可能没有输入",
  },
  F4: {
    numbers: "三高更能承受反复抽取和实际支付，三低较容易付不够",
    roles: "抽取、自损、支付代价后的支援或自强",
    alternative: "低数位有足够资源完成一次支付时，也可把最后一笔成本集中放大",
    watch: "支付为零没有熔炉收益；装备造成的费用不算技能支付",
  },
  F5: {
    numbers: "偏向有原数余量的三高或双高，能承受主阶段先支付、后收款",
    roles: "大笔强化、收尾收益、延迟",
    alternative: "三低也可用它保护大笔收入免遭主阶段截流",
    watch: "依赖即时到账记录或接力的组合会受阻；不是低数不能用",
  },
  F6: {
    numbers: "三高适合多路巩固；混合构成则需要先把支援送到值得保的弱位",
    roles: "自强、多笔支援、保护受援者",
    alternative: "三低可集中建立两条有力量又有护场的赢线",
    watch: "护场抵挡削弱，不能替代原数、支付代价或转移后的资源缺口",
  },
  F7: {
    numbers: "高低差明显的混合构成；并非天然偏三低",
    roles: "自强、先支付代价、动态收款",
    alternative: "接近的三高可以用小额代价轮流争夺下一笔强化",
    watch: "看的是当前力量，不是原数最低者永久收礼",
  },
  F8: {
    numbers: "给低数高技能输出组合一条进攻路线",
    roles: "大笔强化、多目标支援、输出增幅",
    alternative: "三高能保留原数优势，用原本多余的强化压低敌方",
    watch: "会切断依赖友方真正到账的转运和扩散链，敌方防护仍有效",
  },
};
export const sinOf = (id: string) => SINS[id.slice(0, 2) as keyof typeof SINS];
export const card = (id: string) => {
  const c = CARDS.find((x) => x.id === id);
  if (!c) throw Error("Unknown character " + id);
  return c;
};
export const gear = (id: string) => {
  const c = GEARS.find((x) => x.id === id);
  if (!c) throw Error("Unknown gear " + id);
  return c;
};
export function validPlan(id: string, p: number, plan: Plan) {
  const c = card(id);
  if (
    typeof plan.on !== "boolean" ||
    ![0, 1].includes(plan.mode) ||
    !Array.isArray(plan.targets)
  )
    return false;
  if (!plan.on) return plan.targets.length === 0 && plan.mode === 0;
  if ((!c.modes && plan.mode !== 0) || plan.targets.length !== c.targets.length)
    return false;
  if (
    !c.targets.every((t, i) => {
      const x = plan.targets[i];
      return (
        x &&
        Number.isInteger(x.pos) &&
        x.pos >= 0 &&
        x.pos < 3 &&
        x.side === (t === "enemy" ? "enemy" : "ally") &&
        (t !== "other" || x.pos !== p)
      );
    })
  )
    return false;
  return !(
    c.targets.length === 2 &&
    c.targets.every((x) => x !== "enemy") &&
    plan.targets[0].pos === plan.targets[1].pos
  );
}
export const signal = (u: Unit): Signal => ({
  on: u.plan.on,
  kind: u.plan.on ? card(u.id).mark : "off",
  targets: u.plan.on ? structuredClone(u.plan.targets) : [],
});
export function plans(id: string, p: number): Plan[] {
  const c = card(id),
    out: Plan[] = [{ on: false, targets: [], mode: 0 }];
  function add(ts: Plan["targets"]) {
    if (ts.length < c.targets.length) {
      const k = c.targets[ts.length];
      for (let q = 0; q < 3; q++)
        add([...ts, { side: k === "enemy" ? "enemy" : "ally", pos: q }]);
      return;
    }
    for (const mode of (c.modes ? [0, 1] : [0]) as (0 | 1)[]) {
      const a = { on: true, targets: ts, mode };
      if (validPlan(id, p, a)) out.push(a);
    }
  }
  add([]);
  return out;
}
