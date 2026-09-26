import type { Style } from "../ai/agents.js";
import type { Sin } from "../types.js";

/**
 * 炼狱战役的关卡表（设计稿 campaign-v1 §3）：酒馆序章 + 炼狱七姐妹，一共八关。
 * 关卡顺序跟但丁《炼狱篇》的七层，从下往上：傲慢、嫉妒、愤怒、怠惰、贪婪、暴食、色欲。
 *
 * 牌桌参数、对手牌池、台词都是试制内容，要靠模拟和试玩再调。
 */

export interface StageDef {
  /** 0 = 序章，1–7 = 七姐妹。 */
  no: number;
  /** 对手的名字。 */
  foe: string;
  /** 一句话人设。 */
  title: string;
  /** 看板娘是凡人，不属于七罪。 */
  sin: Sin | null;
  /** 这关新学的东西。 */
  teaches: string;
  /** 专属胜利规则；多于一条时每手开局随机翻一条（第 7 关“七罪之约”）。 */
  rules: string[];
  /** 专属规则的名字和说明（第 7 关是一组规则，单独写）。 */
  ruleName: string;
  ruleText: string;
  /** 主场。 */
  arenaId: string;
  /** 主场从第 6 关起才有效果，之前只当背景。 */
  arenaActive: boolean;
  /** 电脑的牌风：novice = 只排位置、排法偏随机（看板娘）。 */
  style: Style | "novice";
  /** 战斗模拟的采样次数（阿斯莫德调到最高）。 */
  samples?: number;
  buyIn: number;
  baseAnte: number;
  blindEvery: number;
  deal: 3 | 4;
  betting: boolean;
  /** 她的固定牌池（8 名，以她的罪为主）。 */
  foePool: string[];
  /** 打败她之后挑人时优先出现的人物（她那一罪的招牌人物）。 */
  signature: string[];
  /** 通关奖励：她的魔神牌（还没做，先只显示名字）。 */
  demon: string | null;
  /** 立绘（web/art/<编号>.webp）；还没画的先用罪的纹样代替。 */
  portrait: string | null;
  /** 关前、关后各一句（完整剧情另做）。 */
  intro: string;
  outro: string;
  /** 输掉之后按重来次数嘲讽：第 1 次、第 2–3 次、第 4–6 次、第 7 次起，每档 2 句。 */
  taunts: [string[], string[], string[], string[]];
}

/** 起始牌池：不依赖下注、不带屏障的 8 名（设计稿 §3.4）。 */
export const STARTING_POOL: readonly string[] = ["WR2", "GR3", "GL1", "GL3", "LU1", "SL4", "GL5", "LU5"];

/** 牌池至少保留几名（挑人之后可以移除 1 名，但不能少于这个数）。 */
export const MIN_CAMPAIGN_POOL = 6;

const SISTER_TABLE = { buyIn: 100, baseAnte: 5, blindEvery: 5, deal: 4, betting: true } as const;

export const STAGES: readonly StageDef[] = [
  {
    no: 0, foe: "看板娘", title: "酒馆的招牌，嘴快，牌技一般但很会教", sin: null,
    teaches: "布阵、对位、碰撞（不下注）",
    rules: ["V01"], ruleName: "酒馆规矩", ruleText: "把对面三个人全部打倒就赢",
    arenaId: "A08", arenaActive: false, style: "novice",
    buyIn: 30, baseAnte: 10, blindEvery: 99, deal: 3, betting: false,
    foePool: ["WR2", "GR3", "GL1", "GL3", "LU1", "SL4", "GL5", "LU5"], signature: [], demon: null, portrait: null,
    intro: "“新来的？这牌叫七罪暗队。先不赌钱，排好你的三个人，看他们自己打。”",
    outro: "“等等，这把不算……哎，蜡烛怎么变成红的了？”",
    taunts: [
      ["“没事没事，第一次都这样。”", "“再来一把？我让你先排。”"],
      ["“你是不是没看对位？”", "“我都快教不下去了。”"],
      ["“要不……你请我喝一杯，我告诉你怎么赢？”", "“老板在看你了，客人。”"],
      ["“你输给看板娘的次数，已经写在酒馆墙上了。”", "“我打烊之前你能赢一把吗？”"],
    ],
  },
  {
    no: 1, foe: "路西法", title: "傲慢 · 长姐，受不了被人无视", sin: "傲慢",
    teaches: "亮 1 暗 2、过牌 / 下注 / 跟注 / 弃牌",
    rules: ["V12"], ruleName: "众目所向", ruleText: "布阵时亮出的那名是旗手，先击倒对方旗手的一方胜",
    arenaId: "A14", arenaActive: false, style: "bluff", ...SISTER_TABLE,
    foePool: ["PR1", "PR3", "WR2", "GR3", "GL3", "LU1", "SL4", "WR3"], signature: ["PR1", "PR2", "PR3"],
    demon: "晨星", portrait: null,
    intro: "“抬头。在我的大厅里，你亮出的那一个，就是你全部的尊严。”",
    outro: "“……你赢的只是一张牌桌，不是我。”",
    taunts: [
      ["“凡人就该低着头。”", "“我甚至没有认真看你。”"],
      ["“你亮出来的，就这点东西？”", "“再来多少次，你都只配跪着。”"],
      ["“我的姐妹们在笑你，听得见吗？”", "“你的尊严已经输得一文不剩了。”"],
      ["“我开始记不清你输了几次，这是对我的冒犯。”", "“要不要我替你排阵？反正结果一样。”"],
    ],
  },
  {
    no: 2, foe: "利维坦", title: "嫉妒 · 话少，总在看别人手里的东西", sin: "嫉妒",
    teaches: "偷看（她先对你用）",
    rules: ["V08"], ruleName: "掐灭火力", ruleText: "攻最高的是核心，先击倒对方核心的一方胜",
    arenaId: "A13", arenaActive: false, style: "cautious", ...SISTER_TABLE,
    foePool: ["EN1", "EN2", "EN4", "PR1", "GL1", "GL3", "LU1", "WR2"], signature: ["EN1", "EN2", "EN4"],
    demon: "深渊之眼", portrait: null,
    intro: "“阿斯莫德看中的人……让我看看，你手里有什么。”",
    outro: "“为什么大家都想要你……我也想要。”",
    taunts: [
      ["“我已经看过你的牌了。”", "“你的核心，藏得太浅。”"],
      ["“你每次都放在同一个位置。”", "“我都不用偷看了。”"],
      ["“阿斯莫德到底看中你哪里？”", "“你的牌，我比你还熟。”"],
      ["“你输的样子，我都收集齐了。”", "“再输一次，我就把你也收进柜子里。”"],
    ],
  },
  {
    no: 3, foe: "撒旦", title: "愤怒 · 急脾气，永远在加注", sin: "愤怒",
    teaches: "加注、奖池",
    rules: ["V03"], ruleName: "连续击破", ruleText: "先击倒两名敌人的一方胜",
    arenaId: "A02", arenaActive: false, style: "aggressive", ...SISTER_TABLE,
    foePool: ["WR1", "WR2", "WR3", "WR4", "EN4", "GL5", "GR3", "LU1"], signature: ["WR1", "WR3", "WR4"],
    demon: "焚怒", portrait: "foe-aggressive",
    intro: "“跟，还是不跟？快点！我没耐心看你发呆！”",
    outro: "“好！再来！……什么，你要走？”",
    taunts: [
      ["“就这？我还没热身！”", "“哈！下一个！”"],
      ["“你到底会不会加注？”", "“别磨蹭，输也输得痛快点！”"],
      ["“我拍桌子都拍累了！”", "“你是来给我送筹码的吧！”"],
      ["“气死我了，你怎么还不赢！”", "“我都想替你加注了！”"],
    ],
  },
  {
    no: 4, foe: "贝尔芬格", title: "怠惰 · 半睡半醒，牌桌就是她的床", sin: "怠惰",
    teaches: "下注强化人物",
    rules: ["V07"], ruleName: "斩旗", ruleText: "血最高的是旗手，先击倒对方旗手的一方胜",
    arenaId: "A03", arenaActive: false, style: "cautious", ...SISTER_TABLE,
    foePool: ["SL1", "SL2", "SL3", "SL4", "WR1", "EN2", "LU1", "GL3"], signature: ["SL1", "SL2", "SL3"],
    demon: "永眠", portrait: null,
    intro: "“……过牌。嗯，再过。你慢慢来，我睡一会儿。”",
    outro: "“……输了？那我可以去睡了吧。”",
    taunts: [
      ["“呼……结束了吗？”", "“我都没怎么动。”"],
      ["“你比我还累的样子。”", "“过牌就能赢，你为什么不试试。”"],
      ["“我做了个梦，梦里你也输了。”", "“再来……让我先躺好。”"],
      ["“你输得太快，我都睡不着了。”", "“……你还在啊。”"],
    ],
  },
  {
    no: 5, foe: "玛门", title: "贪婪 · 记账的，一切都有价", sin: "贪婪",
    teaches: "屏障、连击",
    rules: ["V09"], ruleName: "薄弱环节", ruleText: "血最低的是弱点，先击倒对方弱点的一方胜",
    arenaId: "A06", arenaActive: false, style: "cautious", ...SISTER_TABLE,
    foePool: ["GR1", "GR2", "GR3", "GR4", "PR2", "LU4", "WR4", "SL4"], signature: ["GR1", "GR2", "GR4"],
    demon: "金山", portrait: "foe-cautious",
    intro: "“进门先付利息。你的弱点，我已经标好价了。”",
    outro: "“这一笔算你的。利息，下次再收。”",
    taunts: [
      ["“记账：又一笔坏账。”", "“你欠我的，越来越多了。”"],
      ["“你的弱点，便宜得可怜。”", "“再输，就得拿你自己抵押。”"],
      ["“我已经给你单开了一本账。”", "“这点筹码，还不够付利息。”"],
      ["“恭喜，你是我最大的客户。”", "“账本写满了，你还在输。”"],
    ],
  },
  {
    no: 6, foe: "别西卜", title: "暴食 · 永远在吃，什么注都跟", sin: "暴食",
    teaches: "吞噬、主场效果",
    rules: ["V01"], ruleName: "吃干净", ruleText: "全灭对方即胜",
    arenaId: "A07", arenaActive: true, style: "aggressive", ...SISTER_TABLE,
    foePool: ["GL1", "GL2", "GL3", "GL5", "GR3", "WR2", "SL1", "LU5"], signature: ["GL2", "GL5", "GL1"],
    demon: "万蝇之王", portrait: null,
    intro: "“你也饿吗？坐吧，地牢里水有点深，别介意。”",
    outro: "“吃饱了……你好厉害。下次带点心来？”",
    taunts: [
      ["“嗝。好吃。”", "“还有吗？”"],
      ["“你的人好好吃。”", "“再来一盘！”"],
      ["“我已经不饿了，你还要送吗？”", "“你是来喂我的吧。”"],
      ["“我吃撑了，你让我歇一会儿嘛。”", "“你真是个好人。”"],
    ],
  },
  {
    no: 7, foe: "阿斯莫德", title: "色欲 · 把你拖进来的人，最后亲自坐庄", sin: "色欲",
    teaches: "全部机制的综合",
    rules: ["V12", "V08", "V03", "V07", "V09", "V01"], ruleName: "七罪之约", ruleText: "每手开局从前面几关的规则里随机翻一条",
    arenaId: "A04", arenaActive: true, style: "bluff", samples: 32, ...SISTER_TABLE,
    foePool: ["LU1", "LU2", "LU3", "LU4", "LU5", "PR2", "WR3", "GL2"], signature: ["LU2", "LU3", "LU4"],
    demon: "欲之王", portrait: "foe-bluff",
    intro: "“终于爬上来了。你猜，我亮的是真的吗？”",
    outro: "“……好吧，门开了。可你真的想走吗？”",
    taunts: [
      ["“别急，我喜欢慢慢来。”", "“你输的样子也很好看。”"],
      ["“再陪我玩一次嘛。”", "“你是故意输给我的吧？”"],
      ["“我开始怀疑你是不是不想走了。”", "“姐妹们都在赌你第几次能赢。”"],
      ["“留下来吧，炼狱之馆也不坏。”", "“我都要心疼你了。”"],
    ],
  },
];

export function stage(no: number): StageDef {
  const s = STAGES[no];
  if (!s) throw new Error(`未知关卡：${no}`);
  return s;
}
