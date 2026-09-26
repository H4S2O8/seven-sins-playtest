import { STAGES } from "./stages.js";

/**
 * 战役剧情：每一层的关前、关后对话（设计稿 campaign-v1 §4.1、§4.5）。
 *
 * 一段剧情就是一串台词，画面只负责一句一句播：背景是这一层的主场插画，
 * 说话的人站在前面，名牌上是她的名字。台词按表情差分打了标签，差分画好之后直接换图。
 *
 * - 关前：第一次走进这一层时播（之后在这一层的介绍里可以回看）。
 * - 关后：第一次赢下这一层时播，阿斯莫德每一层都会冒出来说一句（§4.2），最后一层是结局。
 * - 重来过才赢的，关后第一句是她数着你回来的次数（§4.4），`{N}` 换成重来次数。
 *
 * 台词里不出现游戏外的词（序章、关卡、教学、存档……），角色只说她那个世界里的话。
 */

/** 表情差分：设计稿定的五种。 */
export type Mood = "平静" | "得意" | "动摇" | "生气" | "败北";

/** 说话的人：看板娘和七姐妹，按关卡编号对应（名字、罪色、立绘都从 STAGES 里取）；台词不写 who 就是旁白。 */
export const SPEAKERS = {
  barmaid: 0, lucifer: 1, leviathan: 2, satan: 3, belphegor: 4, mammon: 5, beelzebub: 6, asmodeus: 7,
} as const;
export type Speaker = keyof typeof SPEAKERS;

export interface Line {
  /** 谁在说；不写就是旁白。 */
  who?: Speaker;
  mood?: Mood;
  text: string;
  /** 只在重来过才赢的时候说（台词里的 {N} 换成重来次数）。 */
  retried?: true;
}

export type SceneWhen = "before" | "after";

export interface Scene {
  /** 回看、记已读用的编号，如 "s3-before"。 */
  id: string;
  stage: number;
  when: SceneWhen;
  lines: Line[];
}

const say = (who: Speaker, mood: Mood, text: string): Line => ({ who, mood, text });
const nar = (text: string): Line => ({ text });
const again = (who: Speaker, mood: Mood, text: string): Line => ({ who, mood, text, retried: true });

/** 每一层两段：[关前, 关后]。 */
const SCRIPT: Array<[Line[], Line[]]> = [
  // ── 人间酒馆 · 看板娘 ──
  [
    [
      nar("雨下了一整夜。你推开街角那家酒馆的门，炉火噼啪作响，吧台后面的姑娘朝你招手。"),
      say("barmaid", "得意", "来来来，坐！先说好，赢了给小费，输了也给小费。"),
      say("barmaid", "平静", "这牌叫“七罪暗队”。三个人排一排，对着打，把对面三个全打趴下就赢。"),
      say("barmaid", "平静", "头几把不赌钱，大家都亮着打，谁也骗不了谁。我教你，包会。"),
      nar("角落里，一位戴薄纱手套的客人转着一枚筹码，朝这边看了一眼。"),
      say("barmaid", "得意", "别看她，那位客人每晚都来，从来不下场。……好啦，排你的三个人吧！"),
    ],
    [
      again("barmaid", "动摇", "第 {N} 次才赢我？……算了，看在你这么执着的份上，这把我认了。"),
      say("barmaid", "动摇", "等、等一下，刚才那把不算，我手滑了……"),
      nar("桌上的蜡烛忽然矮了一截，火苗由黄转红，红得像要滴下来。"),
      say("barmaid", "动摇", "咦，蜡烛怎么变红了？……喂，你身后那是什么东西？！"),
      say("asmodeus", "得意", "别怕，小丫头。我只是来带走一位客人。"),
      say("asmodeus", "平静", "我看了你一整晚。排人的手很稳，输了也不走……真是个有意思的赌徒。"),
      say("asmodeus", "得意", "来吧，我的小赌徒。楼上有七张牌桌在等你。赢过我们七姐妹，我就放你回来。"),
      nar("红光吞没了酒馆。再睁眼时，你站在一座高塔的最底层，头顶是七扇熄灭的玫瑰窗。"),
    ],
  ],
  // ── 第一层 · 路西法 ──
  [
    [
      nar("第一层是一座空旷的大厅，正中立着一架巨大的天平。天平前摆着牌桌，桌后是一张王座。"),
      say("lucifer", "得意", "抬头，看清楚坐在你对面的是谁。"),
      say("lucifer", "平静", "阿斯莫德又捡回来一个凡人。她总是这样，什么东西都往家里带。"),
      say("lucifer", "平静", "第一层，由我来审你。能站在我面前，已经是你的荣幸。"),
      say("lucifer", "得意", "我的规矩：你亮出的那一个，就是你的旗手。旗手倒下，你就输了。"),
      say("lucifer", "得意", "亮出来吧，凡人。反正在我面前，你什么也藏不住。"),
    ],
    [
      again("lucifer", "平静", "第 {N} 次。在我面前跪了 {N} 次才站起来。……我会记住你的。"),
      say("lucifer", "动摇", "……这一局，是我让你的。记住，是我让的。"),
      nar("头顶第一扇玫瑰窗亮了起来，紫色的光落在牌桌上。"),
      say("lucifer", "败北", "走吧，上面还有六个妹妹。她们可没有我这么仁慈。"),
      nar("楼梯口传来一声轻笑。"),
      say("asmodeus", "得意", "姐姐，脸红了哦。"),
      say("lucifer", "生气", "阿斯莫德！谁准你来看的！"),
      say("asmodeus", "平静", "别生气嘛。我的小赌徒，二姐已经在楼上等你了。她可是盯了你好久。"),
    ],
  ],
  // ── 第二层 · 利维坦 ──
  [
    [
      nar("第二层是一片黑森林。树枝上挂满了别人的东西：手套、怀表、一只断了线的风筝。"),
      say("leviathan", "平静", "……你就是阿斯莫德带回来的那个？……哦。"),
      say("leviathan", "动摇", "路西法姐姐输给你了。……她从来没输过。……真好啊，你。"),
      say("leviathan", "平静", "你的牌……让我看看。就看一眼。"),
      say("leviathan", "得意", "我这里……攻最高的那个，是核心。先倒下的核心……输。"),
      say("leviathan", "平静", "……你的核心，我会先找到的。"),
    ],
    [
      again("leviathan", "平静", "……{N} 次。你回来找了我 {N} 次。……嗯，我记着呢。"),
      say("leviathan", "败北", "……又是这样。别人赢，我看着。"),
      say("leviathan", "动摇", "去吧，去找阿斯莫德。……反正你一开始就是她的。"),
      nar("第二扇玫瑰窗亮了。利维坦把什么东西悄悄挂上了树枝，是你刚才用过的一枚筹码。"),
      say("asmodeus", "得意", "小利维坦，那枚筹码，还给人家。"),
      say("leviathan", "生气", "……不给。"),
      say("asmodeus", "平静", "好吧，留着吧。我的小赌徒，三姐脾气不太好，上楼的时候脚步放轻一点。"),
    ],
  ],
  // ── 第三层 · 撒旦 ──
  [
    [
      nar("还没走到第三层，就听见拍桌子的声音。这里是一座比武场，沙地上全是焦痕。"),
      say("satan", "得意", "喂！终于来了！我手都痒死了！"),
      say("satan", "生气", "利维坦那个闷葫芦都输了？那你肯定有两下子！别让我失望！"),
      say("satan", "平静", "规矩就一条：先打倒对面两个人的赢！简单吧？"),
      say("satan", "生气", "跟，还是不跟？快点！我没耐心看你发呆！"),
    ],
    [
      again("satan", "得意", "第 {N} 次！哈，你跟我一样倔！我喜欢！"),
      say("satan", "生气", "啊啊啊！（拍桌）……行，你有种。我认！"),
      say("satan", "败北", "输就输！下次我加注加到你哭！"),
      nar("第三扇玫瑰窗亮起，红光里还带着火星。"),
      say("asmodeus", "得意", "三姐，这已经是这个月拍坏的第四张桌子了。"),
      say("satan", "生气", "要你管！"),
      say("asmodeus", "平静", "上面是四姐的院子。她要是睡着了，你就……算了，她一直睡着。"),
    ],
  ],
  // ── 第四层 · 贝尔芬格 ──
  [
    [
      nar("第四层下着雪。院子正中摆着牌桌，桌上趴着一个裹着毛毯的人。你等了很久，她才翻了个身。"),
      say("belphegor", "平静", "哈啊～……你来了啊。撒旦吵了一上午……原来是因为你。"),
      say("belphegor", "平静", "规矩……血最多的那个是旗手……旗手倒了就输……嗯，就这样。"),
      say("belphegor", "平静", "我过牌。……嗯，一直过。"),
      say("belphegor", "得意", "别吵我哦……我会越睡越强的……zzz"),
    ],
    [
      again("belphegor", "平静", "{N} 次……好勤快哦……光听着就累了……"),
      say("belphegor", "败北", "……输了啊。也好……这下终于能好好睡一觉了……"),
      say("belphegor", "平静", "上楼吧……楼梯好长……我就不送了……"),
      nar("第四扇玫瑰窗亮了。雪停了，院子里只剩她均匀的呼吸声。"),
      say("asmodeus", "得意", "她是真的睡着了。……你要不要给她把毯子盖好？"),
      say("asmodeus", "平静", "上面是五姐的宝库。进门之前，把口袋捂紧一点。"),
    ],
  ],
  // ── 第五层 · 玛门 ──
  [
    [
      nar("第五层堆满了金币，一直堆到穹顶。金山中间坐着一个戴单片眼镜的人，正在翻账簿。"),
      say("mammon", "平静", "欢迎光临第五层。在这里，每一枚筹码都有它的价格。"),
      say("mammon", "得意", "您连赢四位，我那几位姐妹欠我的账更难收了。这笔损失，我打算记在您头上。"),
      say("mammon", "平静", "我的规矩：血最少的那一位是弱点，弱点先倒下的一方输。弱点，自然也有标价。"),
      say("mammon", "平静", "请放心，我从不做亏本的买卖。所以，请您尽情地亏。"),
    ],
    [
      again("mammon", "平静", "{N} 次挑战，每次都输光本金。按我的利率算，您已经欠我一座金山了。"),
      say("mammon", "动摇", "……亏损。这是我账上第一笔亏损。"),
      say("mammon", "败北", "我认账。不过，您从我这里拿走的，迟早要连本带利还回来。"),
      nar("第五扇玫瑰窗亮了。她提起笔，在你的名字下面画了一道线。"),
      say("asmodeus", "得意", "玛门姐姐，账上还记着我的名字吗？"),
      say("mammon", "平静", "记着。您欠的，是最多的。"),
      say("asmodeus", "平静", "……我们上楼吧，我的小赌徒。六姐肚子饿了，别让她等太久。"),
    ],
  ],
  // ── 第六层 · 别西卜 ──
  [
    [
      nar("第六层的台阶泡在水里。地牢深处飘来甜腻的香味，还有咀嚼的声音。"),
      say("beelzebub", "得意", "你来啦！要不要吃点？……不要？那我自己吃了。"),
      say("beelzebub", "平静", "玛门姐姐刚才下来找点心，说她亏钱了，哭得好伤心。是你干的吧？好厉害！"),
      say("beelzebub", "平静", "我这里的规矩最简单：把对面吃干净就赢。"),
      say("beelzebub", "动摇", "对了，地牢的水有点深。在这里挨一下，水花会溅到旁边的人身上哦。"),
      say("beelzebub", "得意", "打牌好饿哦……赢的人请客好不好？"),
    ],
    [
      again("beelzebub", "得意", "{N} 次！你来了这么多次，我都多吃了 {N} 顿夜宵！"),
      say("beelzebub", "败北", "输了……好饿……你走之前能把剩下的点心留给我吗？"),
      say("beelzebub", "平静", "你好厉害！下次来，我请你吃饭，真的！"),
      nar("第六扇玫瑰窗亮了。整座塔里，只剩最顶上那一扇还黑着。"),
      say("asmodeus", "得意", "六扇了。……真快啊。"),
      say("asmodeus", "平静", "上来吧，我的小赌徒。最后一张牌桌，我亲自坐庄。"),
    ],
  ],
  // ── 第七层 · 阿斯莫德 ──
  [
    [
      nar("塔顶是一口许愿井，井底沉满了筹码。阿斯莫德坐在井沿上，转着那枚筹码。"),
      say("asmodeus", "得意", "终于爬上来了呀，我的小赌徒。我等你好久了。"),
      say("asmodeus", "平静", "从酒馆那一晚起，我就在看你。现在，轮到我亲自发牌了。"),
      say("asmodeus", "平静", "姐姐们的规矩，你都见过了。今晚每一手，我都从里面翻一条。"),
      say("asmodeus", "平静", "井水会护着还没出手的人。所以，别急着扑上来。"),
      say("asmodeus", "得意", "猜猜看，我会给你哪一条？"),
    ],
    [
      again("asmodeus", "得意", "第 {N} 次。你为我回来了 {N} 次，我可是一次一次数着的哦。"),
      say("asmodeus", "动摇", "……赢了我？呵，我果然没看错人。"),
      nar("最后一扇玫瑰窗亮了。七种颜色的光一起落下来，塔底那扇门吱呀一声开了。"),
      say("asmodeus", "败北", "门就在那里，你可以走了。"),
      nar("门外传来酒馆的喧闹声，还有一声熟悉的吆喝。"),
      say("barmaid", "生气", "客人！你的小费还没给呢！"),
      say("asmodeus", "得意", "……不过，你真的想走吗？"),
      say("asmodeus", "平静", "去吧。想我们的时候，楼梯一直都在。"),
    ],
  ],
];

export const SCENES: readonly Scene[] = SCRIPT.flatMap(([before, after], stage) => [
  { id: `s${stage}-before`, stage, when: "before" as const, lines: before },
  { id: `s${stage}-after`, stage, when: "after" as const, lines: after },
]);

export function scene(stage: number, when: SceneWhen): Scene {
  const s = SCENES.find((x) => x.stage === stage && x.when === when);
  if (!s) throw new Error(`没有这段剧情：${stage} ${when}`);
  return s;
}

/** 这一次实际要播的台词：没重来过就去掉提重来次数的那句，{N} 填成重来次数。 */
export function linesFor(sc: Scene, retries: number): Line[] {
  return sc.lines
    .filter((l) => !l.retried || retries > 0)
    .map((l) => (l.text.includes("{N}") ? { ...l, text: l.text.replaceAll("{N}", String(retries)) } : l));
}

/** 说话的人对应的关卡（名字、罪色、立绘都跟着关卡表走）。 */
export function speakerStage(who: Speaker) {
  return STAGES[SPEAKERS[who]];
}

/** 这一层的主人（剧情里站在左边的人）。 */
export function hostOf(stage: number): Speaker {
  const who = (Object.keys(SPEAKERS) as Speaker[]).find((w) => SPEAKERS[w] === stage);
  if (!who) throw new Error(`这一层没有主人：${stage}`);
  return who;
}
