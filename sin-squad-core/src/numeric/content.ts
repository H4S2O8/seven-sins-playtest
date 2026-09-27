/** Isolated numeric-mode content. Text and execution are derived from the same rules. */
export type NumericEquipmentTier = "normal" | "replace-1" | "replace-2";
export type NumericSeat = 0 | 1;
export interface NumericSlot { number: number; effectId: string; equipment: { id: string; tier: NumericEquipmentTier } | null }
export interface NumericTeam { slots: (NumericSlot | null)[] }
export interface NumericStats { invested?: number; betOrRaise?: number; betOrRaiseCount?: number; checks?: number; opsPaid?: number; stack?: number; round?: number }
export interface NumericCard { id: string; name: string; text: string; kind: string }
type Ref = "raw" | "foeRaw" | "leftRaw" | "rightRaw" | "otherRawSum" | "teamRawSum" | "foeRawSum" | "teamRawMax" | "teamRawMin" | "foeRawMax" | "foeRawMin" | "pos" | "equipCount" | "foeEquip" | "ownEquip" | "invested" | "raises" | "foeRaises" | "checks" | "ops" | "stack" | "foeStack" | "round" | "silenced" | "foeSilenced" | "environmentPower";
type Expr = number | Ref | { op: "add" | "sub" | "mul" | "div" | "min" | "max" | "abs"; args: Expr[] };
type Cond = { left: Expr; cmp: "<" | "<=" | "=" | ">=" | ">" | "!="; right: Expr } | { all: Cond[] } | { any: Cond[] };
type Target = "self" | "foe" | "left" | "right" | "neighbors" | "others" | "team";
type Action = { kind: "power"; target: Target; amount: Expr } | { kind: "silence" | "seal"; target: Target };
export interface NumericClause { when?: Cond; actions: Action[] }
export interface NumericCharacter extends NumericCard { tag: string; rules: NumericClause[] }
export interface NumericEquipment extends NumericCard { tier: NumericEquipmentTier; rules: NumericClause[] }
export interface NumericArena extends NumericCard { rules: NumericClause[] }
export interface NumericEffect extends NumericCard { rules: NumericClause[] }
type ScoreMetric = "wins" | "sum" | "centerWin" | "edgeWins" | "upsets" | "silentWins" | "minPower" | "maxPower" | "cappedMargins";
export interface NumericRule extends NumericCard { metrics: ScoreMetric[] }
export interface NumericTrace { sourceId: string; seat: NumericSeat; pos: number; targetSeat: NumericSeat; targetPos: number; before: number; after: number; text: string; stage: "environment" | "control" | "character" | "equipment" }
export interface NumericResolution { winner: NumericSeat | null; powers: [number[], number[]]; lineWinners: (NumericSeat | null)[]; lines: string[]; scores: [number, number]; scoreVectors: [number[], number[]]; trace: NumericTrace[]; silenced: [boolean[], boolean[]]; sealed: [boolean[], boolean[]]; teams: [NumericTeam, NumericTeam] }
export interface NumericResolutionInput { teams: [NumericTeam, NumericTeam] | [NumericSlot[], NumericSlot[]]; arenaId: string; ruleId: string; activeEffectIds?: string[]; stats?: [NumericStats, NumericStats] | { pot: number }; recordTrace?: boolean }

const E = (op: "add" | "sub" | "mul" | "div" | "min" | "max" | "abs", ...args: Expr[]): Expr => ({ op, args });
const cmp = (left: Expr, comparison: "<" | "<=" | "=" | ">=" | ">" | "!=", right: Expr): Cond => ({ left, cmp: comparison, right });
const all = (...conditions: Cond[]): Cond => ({ all: conditions });
const any = (...conditions: Cond[]): Cond => ({ any: conditions });
const power = (amount: Expr, target: Target = "self"): Action => ({ kind: "power", amount, target });
const silence = (target: Target): Action => ({ kind: "silence", target });
const seal = (target: Target): Action => ({ kind: "seal", target });
const rule = (actions: Action[], when?: Cond): NumericClause => ({ actions, when });
const selfLow = cmp("raw", "<=", 4), selfHigh = cmp("raw", ">=", 8), foeHigh = cmp("foeRaw", ">=", 8);
const hasFoeEquipment = cmp("foeEquip", "=", 1);
const higherBy = (n: number) => cmp(E("sub", "raw", "foeRaw"), ">=", n);
const lowerBy = (n: number) => cmp(E("sub", "foeRaw", "raw"), ">=", n);
const posIs = (n: number) => cmp("pos", "=", n);
const RAW_LABEL: Record<Ref, string> = {
  raw: "自身原始数字", foeRaw: "对位原始数字", leftRaw: "左邻原始数字", rightRaw: "右邻原始数字", otherRawSum: "己方另外两位原始数字总和", teamRawSum: "己方原始数字总和", foeRawSum: "敌方原始数字总和", teamRawMax: "己方最高原始数字", teamRawMin: "己方最低原始数字", foeRawMax: "敌方最高原始数字", foeRawMin: "敌方最低原始数字", pos: "所在位置", equipCount: "己方已装备的位置数", foeEquip: "对位有装备（有=1，无=0）", ownEquip: "自身有装备（有=1，无=0）", invested: "己方本手投入筹码", raises: "己方本手主动下注/加注次数", foeRaises: "对手本手主动下注/加注次数", checks: "己方本手过牌次数", ops: "己方本手支付装备操作费次数", stack: "己方剩余筹码", foeStack: "对手剩余筹码", round: "本手进行到的下注轮数", silenced: "自身人物被沉默（是=1，否=0）", foeSilenced: "对位人物被沉默（是=1，否=0）", environmentPower: "场地阶段结束时自身力量" };
function exprText(v: Expr): string {
  if (typeof v === "number") return String(v);
  if (typeof v === "string") return RAW_LABEL[v];
  const a = v.args.map(exprText);
  if (v.op === "min") return typeof v.args[0] === "number" ? `${a[1]}（最多 ${a[0]}）` : `两者较小值（${a.join("，")}）`;
  if (v.op === "max") return v.args[0] === 0 ? `${a[1]}（最低为 0）` : `两者较大值（${a.join("，")}）`;
  if (v.op === "abs") return `绝对值(${a[0]})`;
  if (v.op === "div") return `（${a[0]} ÷ ${a[1]}，舍去小数）`;
  return `(${a.join(v.op === "add" ? " + " : v.op === "sub" ? " − " : " × ")})`;
}
function conditionText(c: Cond): string { return "all" in c ? c.all.map(conditionText).join("且") : "any" in c ? `（${c.any.map(conditionText).join("或")}）` : `${exprText(c.left)} ${c.cmp} ${exprText(c.right)}`; }
const TARGET_TEXT: Record<Target, string> = { self: "自身", foe: "对位", left: "左邻", right: "右邻", neighbors: "左右相邻队友", others: "己方另外两位", team: "己方三位" };
function actionText(a: Action): string {
  if (a.kind === "silence") return `沉默${TARGET_TEXT[a.target]}人物效果`;
  if (a.kind === "seal") return `封印${TARGET_TEXT[a.target]}装备效果`;
  if (a.kind !== "power") return "";
  if (typeof a.amount === "number") return `${TARGET_TEXT[a.target]}力量 ${a.amount >= 0 ? "+" : "−"}${Math.abs(a.amount)}`;
  return `${TARGET_TEXT[a.target]}力量增加 ${exprText(a.amount)}`;
}
export function numericRulesText(rules: NumericClause[]): string { return rules.map(r => `${r.when ? `若${conditionText(r.when)}：` : ""}${r.actions.map(actionText).join("；")}`).join("。") + "。"; }
function card<T extends NumericCard>(data: Omit<T, "text"> & { rules: NumericClause[] }): T { return { ...data, text: numericRulesText(data.rules) } as unknown as T; }
const ch = (id: string, name: string, tag: string, rules: NumericClause[]): NumericCharacter => card<NumericCharacter>({ id, name, tag, kind: "人物效果", rules });

/** All 29 original character names/IDs are retained. No ability needs health, damage, or changing targets. */
export const NUMERIC_CHARACTERS: readonly NumericCharacter[] = [
  ch("WR1", "小红帽", "反加注", [rule([power(E("min", 3, "foeRaises"))])]),
  ch("WR2", "狂战士", "以小搏大", [rule([power(4)], lowerBy(2))]),
  ch("WR3", "清算者", "重注清算", [rule([power(E("div", "raw", 2))], cmp("foeRaises", ">", 0))]),
  ch("GR1", "豪商", "花钱养成", [rule([power(E("min", 4, E("div", "invested", 10)))])]),
  ch("GR2", "赎罪券商", "付费积累", [rule([power(E("min", 3, "ops"))])]),
  ch("GR3", "收藏家", "装备收藏", [rule([power("equipCount")])]),
  ch("GL1", "放血师", "力量汲取", [rule([power(2), power(-2, "foe")], lowerBy(1))]),
  ch("GL2", "饕餮", "吞食左邻", [rule([silence("left"), power(E("div", "leftRaw", 2))], cmp("pos", ">", 1))]),
  ch("GL3", "食腐鸦", "弱位拾遗", [rule([power(3)], all(cmp("raw", "=", "teamRawMin"), cmp("foeRaw", "<=", 7)))]),
  ch("EN1", "密探", "精确猜测", [rule([power(3)], cmp(E("abs", E("sub", "raw", "foeRaw")), "<=", 1))]),
  ch("EN2", "镜中人", "映照原数", [rule([power(E("max", 0, E("sub", "foeRaw", "raw")))])]),
  ch("EN3", "扒手", "装备截取", [rule([seal("foe"), power(1)], hasFoeEquipment)]),
  ch("SL1", "冬眠熊", "过牌蓄力", [rule([power(E("min", 3, "checks"))])]),
  ch("SL2", "沉眠巨像", "小数翻倍", [rule([power("raw")], selfLow)]),
  ch("SL3", "隐修士", "节制庇护", [rule([power(1, "team")], cmp("ops", "=", 0))]),
  ch("PR1", "孔雀", "高位压制", [rule([power(2)], selfHigh)]),
  ch("PR2", "无瑕刺客", "悬殊一击", [rule([power(E("div", "raw", 2))], higherBy(3))]),
  ch("PR3", "僭王", "王权号令", [rule([power(2, "others")], all(cmp("raw", "=", "teamRawMax"), selfHigh))]),
  ch("LU1", "痴情骑士", "牺牲守护", [rule([power(-2), power(2, "neighbors")])]),
  ch("LU2", "牵线人", "缔结静默", [rule([silence("self"), silence("foe")])]),
  ch("LU3", "塞壬", "魅惑强者", [rule([power(-3, "foe")], lowerBy(1))]),
  ch("WR4", "攻城锤手", "破装强攻", [rule([power(3)], hasFoeEquipment)]),
  ch("GR4", "金库守卫", "守财优势", [rule([power(3)], cmp("stack", ">", "foeStack"))]),
  ch("GL4", "噬铁软泥", "腐蚀装备", [rule([power(-2, "foe")], hasFoeEquipment)]),
  ch("GL5", "大野狼", "追猎弱位", [rule([power(3)], cmp("foeRaw", "=", "foeRawMin"))]),
  ch("EN4", "影子", "高位影袭", [rule([power(3)], foeHigh)]),
  ch("SL4", "守夜人", "后程发力", [rule([power(3)], cmp("round", ">=", 4))]),
  ch("LU4", "交际花", "借势削弱", [rule([power(-2, "foe"), power(1, "right")], lowerBy(1))]),
  ch("LU5", "双子", "中央联动", [rule([power(1, "team")], posIs(2))]),
];
export const NUMERIC_CHARACTER_IDS: readonly string[] = NUMERIC_CHARACTERS.map(c => c.id);

/** Same equipment mechanism at three magnitudes; an installed copy retains its original tier. */
type EquipmentDesign = { id: string; name: string; kind: string; rules: (v: number) => NumericClause[]; magnitudes: [number, number, number] };
const equip = (id: string, name: string, kind: string, rules: (v: number) => NumericClause[], magnitudes: [number, number, number] = [3, 2, 1]): EquipmentDesign => ({ id, name, kind, rules, magnitudes });
const EQUIPMENT_DESIGNS: EquipmentDesign[] = [
  equip("E01", "校准刃", "基础", v => [rule([power(v)])]),
  equip("E02", "厚衬背心", "低数", v => [rule([power(v)], selfLow)], [5, 3, 1]),
  equip("E03", "轻摆齿轮", "中数", v => [rule([power(v)], all(cmp("raw", ">=", 5), cmp("raw", "<=", 7)))], [4, 2, 1]),
  equip("E04", "铁拳套", "压小", v => [rule([power(v)], cmp("foeRaw", "<=", 4))], [5, 3, 1]),
  equip("E05", "行军斗篷", "左位支援", v => [rule([power(v, "left")])], [4, 2, 1]),
  equip("E06", "猎刀", "追猎弱位", v => [rule([power(v)], cmp("foeRaw", "=", "foeRawMin"))], [4, 2, 1]),
  equip("E07", "双刃", "反高", v => [rule([power(v)], foeHigh)], [5, 3, 1]),
  equip("E08", "磨刀石", "高数", v => [rule([power(v)], selfHigh)], [4, 2, 1]),
  equip("E09", "铁衬", "边位", v => [rule([power(v)], cmp("pos", "!=", 2))], [4, 2, 1]),
  equip("E10", "链甲", "队伍联动", v => [rule([power(v)], cmp("otherRawSum", ">=", 14))], [5, 3, 1]),
  equip("E11", "护符", "低位补偿", v => [rule([power(v)], cmp("raw", "=", "teamRawMin"))], [4, 2, 1]),
  equip("E12", "镜符", "同数针对", v => [rule([power(v)], cmp("raw", "=", "foeRaw"))], [6, 3, 1]),
  equip("E13", "逆差线圈", "以小搏大", v => [rule([power(v)], lowerBy(3))], [6, 3, 1]),
  equip("E14", "右翼扣", "右位支援", v => [rule([power(v, "right")])], [4, 2, 1]),
  equip("E15", "双翼连杆", "双线支援", v => [rule([power(v, "others")], all(posIs(2), selfHigh))]),
  equip("E16", "夹心垫", "夹心阵", v => [rule([power(v)], all(posIs(2), cmp("leftRaw", ">", "raw"), cmp("rightRaw", ">", "raw")))], [6, 3, 1]),
  equip("E17", "山峰冠", "山峰阵", v => [rule([power(v)], all(posIs(2), cmp("leftRaw", "<", "raw"), cmp("rightRaw", "<", "raw")))], [5, 3, 1]),
  equip("E18", "逆风帆", "整队逆差", v => [rule([power(v)], cmp("teamRawSum", "<", "foeRawSum"))], [4, 2, 1]),
  equip("E19", "顺风旗", "整队压制", v => [rule([power(v)], cmp("teamRawMin", ">=", 7))], [5, 3, 1]),
  equip("E20", "静默保险", "沉默补偿", v => [rule([power(v)], cmp("silenced", "=", 1))], [5, 3, 1]),
  equip("E21", "封口钉", "沉默针对", v => [rule([power(v)], cmp("foeSilenced", "=", 1))], [5, 3, 1]),
  equip("E22", "借力滑轮", "混合比较", v => [rule([power(v)], all(cmp("otherRawSum", ">=", E("mul", "raw", 2)), lowerBy(1)))], [6, 3, 1]),
  equip("E23", "等差尺", "数字结构", v => [rule([power(v)], all(posIs(2), cmp(E("sub", "raw", "leftRaw"), "=", E("sub", "rightRaw", "raw"))))], [5, 3, 1]),
  equip("E24", "互惠结", "双边条件", v => [rule([power(v)], all(cmp("leftRaw", ">=", 8), cmp("foeRaw", "<=", 4)))], [6, 3, 1]),
];
const tierIndex: Record<NumericEquipmentTier, number> = { normal: 0, "replace-1": 1, "replace-2": 2 };
export function equipmentById(id: string, tier: NumericEquipmentTier = "normal"): NumericEquipment {
  const d = EQUIPMENT_DESIGNS.find(c => c.id === id);
  if (!d) throw new Error(`未知数字装备：${id}`);
  if (!(tier in tierIndex)) throw new Error(`未知装备档位：${tier}`);
  return card<NumericEquipment>({ id: d.id, name: d.name, kind: d.kind, tier, rules: d.rules(d.magnitudes[tierIndex[tier]]) });
}
export const NUMERIC_EQUIPMENT: readonly NumericEquipment[] = EQUIPMENT_DESIGNS.map(c => equipmentById(c.id));
const env = (id: string, name: string, kind: string, rules: NumericClause[]): NumericArena => card<NumericArena>({ id, name, kind, rules });
export const NUMERIC_ARENAS: readonly NumericArena[] = [
  env("NA01", "比武场", "高位压制", [rule([power(1)], higherBy(1))]),
  env("NA02", "天平大厅", "分摊数字", [rule([power(E("max", 0, E("div", E("sub", "otherRawSum", E("mul", "raw", 2)), 3)))])]),
  env("NA03", "崩落阶梯", "位置差异", [rule([power(E("div", "raw", 3))], posIs(1)), rule([power(1)], posIs(2)), rule([power(E("max", 0, E("sub", 7, "raw")))], posIs(3))]),
  env("NA04", "许愿井", "低数成长", [rule([power(E("div", "raw", 2))], cmp("raw", "<=", 5))]),
  env("NA05", "静默书库", "纯数字", [rule([silence("self")])]),
  env("NA06", "巨龙宝库", "强者相邻", [rule([power(1)], cmp("leftRaw", ">=", 8)), rule([power(1)], cmp("rightRaw", ">=", 8))]),
  env("NA07", "黑森林", "低高克制", [rule([power(3)], all(selfLow, foeHigh)), rule([power(-1)], all(selfHigh, cmp("foeRaw", "<=", 4)))]),
  env("NA08", "高塔倾覆", "峰谷调整", [rule([power(-2)], cmp("raw", "=", "teamRawMax")), rule([power(1)], cmp("raw", "=", "teamRawMin"))]),
];
export const NUMERIC_EFFECTS: readonly NumericEffect[] = [
  env("NF01", "高压", "高数", [rule([power(E("div", "raw", 4))])]),
  env("NF02", "低伏", "低数", [rule([power(E("max", 0, E("sub", 6, "raw")))])]),
  env("NF03", "中央聚光", "位置", [rule([power(E("div", "raw", 2))], posIs(2))]),
  env("NF04", "双翼传灯", "双翼", [rule([power(2, "right")], all(posIs(1), cmp("raw", "<=", "rightRaw"))), rule([power(2, "left")], all(posIs(3), cmp("raw", "<=", "leftRaw")))]),
  env("NF05", "背水", "逆差", [rule([power(3)], lowerBy(3))]),
  env("NF06", "同阶封锁", "沉默", [rule([silence("self")], any(all(selfLow, cmp("foeRaw", "<=", 4)), all(cmp("raw", ">=", 5), cmp("raw", "<=", 7), cmp("foeRaw", ">=", 5), cmp("foeRaw", "<=", 7)), all(selfHigh, foeHigh)))]),
  env("NF07", "禁言席", "中央沉默", [rule([silence("self"), power(2)], posIs(2))]),
  env("NF08", "左右手", "位置差异", [rule([power(2)], all(posIs(1), selfLow)), rule([power(2)], all(posIs(3), selfHigh))]),
  env("NF09", "等差共鸣", "数字结构", [rule([power(3)], all(posIs(2), cmp(E("sub", "raw", "leftRaw"), "=", E("sub", "rightRaw", "raw"))))]),
  env("NF10", "碎械节", "装备封印", [rule([seal("self")], cmp("raw", "=", "teamRawMax"))]),
  env("NF11", "夹谷回声", "高低结构", [rule([power(3)], all(posIs(2), cmp("leftRaw", ">", "raw"), cmp("rightRaw", ">", "raw")))]),
  env("NF12", "末席薪火", "末席支援", [rule([power(2, "left")], all(posIs(3), selfLow))]),
];
const SCORE_TEXT: Record<ScoreMetric, string> = { wins: "赢线数", sum: "最终力量总和", centerWin: "2号位是否获胜（胜=1，其他=0）", edgeWins: "1、3号位赢线数", upsets: "原始数字低于对位且赢线的数量", silentWins: "己方人物被沉默且赢线的数量", minPower: "己方最低最终力量", maxPower: "己方最高最终力量", cappedMargins: "各条赢线领先值之和（每线最多记3）" };
const victory = (id: string, name: string, kind: string, metrics: ScoreMetric[]): NumericRule => ({ id, name, kind, metrics, text: `依次比较${metrics.map(m => SCORE_TEXT[m]).join("，再比较")}；首次不同处较高者胜；全部相同则平分奖池。` });
export const NUMERIC_RULES: readonly NumericRule[] = [
  victory("NR01", "两线推进", "赢线", ["wins", "sum"]),
  victory("NR02", "中央裁决", "中央", ["centerWin", "wins", "sum"]),
  victory("NR03", "双翼包围", "边线", ["edgeWins", "wins", "sum"]),
  victory("NR04", "绝境突围", "以小胜大", ["upsets", "wins", "sum"]),
  victory("NR05", "全面压进", "总力", ["sum", "wins"]),
  victory("NR06", "无缺口阵线", "最低线", ["minPower", "wins", "sum"]),
  victory("NR07", "持续优势", "赢幅", ["cappedMargins", "wins", "sum"]),
  victory("NR08", "静默审判", "沉默赢线", ["silentWins", "wins", "sum"]),
];
function lookup<T extends NumericCard>(cards: readonly T[], id: string): T { const c = cards.find(x => x.id === id); if (!c) throw new Error(`未知数字牌：${id}`); return c; }
export const characterById = (id: string): NumericCharacter => lookup(NUMERIC_CHARACTERS, id);
export const arenaById = (id: string): NumericArena => lookup(NUMERIC_ARENAS, id);
export const ruleById = (id: string): NumericRule => lookup(NUMERIC_RULES, id);
export const effectById = (id: string): NumericEffect => lookup(NUMERIC_EFFECTS, id);
export const numericCharacter = characterById, numericEquipment = equipmentById, numericArena = arenaById, numericRule = ruleById, numericEffect = effectById;

interface Context { seat: NumericSeat; pos: number; teams: NumericSlot[][]; stats: NumericStats[]; environment: number[][]; silenced: boolean[][]; sealed: boolean[][] }
const other = (s: NumericSeat): NumericSeat => s === 0 ? 1 : 0;
const total = (ns: number[]) => ns.reduce((a, b) => a + b, 0);
function reference(name: Ref, c: Context): number {
  const own = c.teams[c.seat], enemy = c.teams[other(c.seat)], slot = own[c.pos], foe = enemy[c.pos], nums = own.map(s => s.number), foes = enemy.map(s => s.number), s = c.stats[c.seat], e = c.stats[other(c.seat)];
  const raw: Record<Ref, number> = { raw: slot.number, foeRaw: foe.number, leftRaw: own[c.pos - 1]?.number ?? 0, rightRaw: own[c.pos + 1]?.number ?? 0, otherRawSum: total(nums) - slot.number, teamRawSum: total(nums), foeRawSum: total(foes), teamRawMax: Math.max(...nums), teamRawMin: Math.min(...nums), foeRawMax: Math.max(...foes), foeRawMin: Math.min(...foes), pos: c.pos + 1, equipCount: own.filter(s => s.equipment).length, foeEquip: Number(!!foe.equipment), ownEquip: Number(!!slot.equipment), invested: s.invested ?? 0, raises: s.betOrRaise ?? s.betOrRaiseCount ?? 0, foeRaises: e.betOrRaise ?? e.betOrRaiseCount ?? 0, checks: s.checks ?? 0, ops: s.opsPaid ?? 0, stack: s.stack ?? 0, foeStack: e.stack ?? 0, round: s.round ?? 1, silenced: Number(c.silenced[c.seat][c.pos]), foeSilenced: Number(c.silenced[other(c.seat)][c.pos]), environmentPower: c.environment[c.seat][c.pos] };
  return raw[name];
}
function evaluate(e: Expr, c: Context): number {
  if (typeof e === "number") return e;
  if (typeof e === "string") return reference(e, c);
  const n = e.args.map(x => evaluate(x, c));
  switch (e.op) { case "add": return total(n); case "sub": return n[0] - n[1]; case "mul": return n[0] * n[1]; case "div": return Math.floor(n[0] / n[1]); case "min": return Math.min(...n); case "max": return Math.max(...n); case "abs": return Math.abs(n[0]); }
}
function matches(x: Cond | undefined, c: Context): boolean {
  if (!x) return true;
  if ("all" in x) return x.all.every(a => matches(a, c));
  if ("any" in x) return x.any.some(a => matches(a, c));
  const a = evaluate(x.left, c), b = evaluate(x.right, c);
  switch (x.cmp) { case "<": return a < b; case "<=": return a <= b; case "=": return a === b; case ">=": return a >= b; case ">": return a > b; case "!=": return a !== b; }
}
function targets(target: Target, c: Context): [NumericSeat, number][] {
  switch (target) { case "self": return [[c.seat, c.pos]]; case "foe": return [[other(c.seat), c.pos]]; case "left": return c.pos > 0 ? [[c.seat, c.pos - 1]] : []; case "right": return c.pos < 2 ? [[c.seat, c.pos + 1]] : []; case "neighbors": return [c.pos - 1, c.pos + 1].filter(p => p >= 0 && p < 3).map(p => [c.seat, p]); case "others": return [0, 1, 2].filter(p => p !== c.pos).map(p => [c.seat, p]); case "team": return [0, 1, 2].map(p => [c.seat, p]); }
}
type Packet = { sourceId: string; text: string; ctx: Context; action: Action; targetSeat: NumericSeat; targetPos: number; amount: number };
function packets(card: NumericCard & { rules: NumericClause[] }, ctx: Context, recordTrace = true): Packet[] {
  return card.rules.flatMap(r => matches(r.when, ctx) ? r.actions.flatMap(a => targets(a.target, ctx).map(([targetSeat, targetPos]) => ({ sourceId: card.id, text: recordTrace ? numericRulesText([r]) : "", ctx, action: a, targetSeat, targetPos, amount: a.kind === "power" ? evaluate(a.amount, ctx) : 0 }))) : []);
}

/**
 * Deterministic reveal: environment deltas are simultaneous; then character control
 * is locked simultaneously from the environment snapshot; then live character
 * power, then unsealed equipment power. Silencing never undoes already locked
 * control. All arithmetic is integer, no health/damage/death/aiming is involved.
 */
export function runNumericResolution(input: NumericResolutionInput): NumericResolution {
  const teams: [NumericTeam, NumericTeam] = input.teams.map(t => ({ slots: Array.isArray(t) ? t : t.slots })) as [NumericTeam, NumericTeam];
  if (teams.some(t => t.slots.length !== 3 || t.slots.some(s => !s || !Number.isInteger(s.number) || s.number < 3 || s.number > 10))) throw new Error("数字模式必须由每方三个 3～10 的整数原始数字组成");
  const slots = teams.map(t => t.slots as NumericSlot[]);
  slots.flat().forEach(s => { characterById(s.effectId); if (s.equipment) equipmentById(s.equipment.id, s.equipment.tier); });
  const arena = arenaById(input.arenaId), victoryRule = ruleById(input.ruleId);
  const effectIds = input.activeEffectIds ?? [];
  if (new Set(effectIds).size !== effectIds.length) throw new Error("同一张场地效果不能重复启用");
  const effects = effectIds.map(effectById);
  const stats: NumericStats[] = Array.isArray(input.stats) ? input.stats : [{}, {}];
  const powers = slots.map(t => t.map(s => s.number)) as [number[], number[]];
  const silenced: [boolean[], boolean[]] = [[false, false, false], [false, false, false]], sealed: [boolean[], boolean[]] = [[false, false, false], [false, false, false]];
  const trace: NumericTrace[] = [];
  const makePackets = (card: NumericCard & { rules: NumericClause[] }, ctx: Context) => packets(card, ctx, input.recordTrace !== false);
  let environment = powers.map(p => [...p]);
  const contexts = () => ([0, 1] as NumericSeat[]).flatMap(seat => [0, 1, 2].map(pos => ({ seat, pos, teams: slots, stats, environment, silenced: silenced.map(t => [...t]), sealed: sealed.map(t => [...t]) })));
  const apply = (ps: Packet[], stage: NumericTrace["stage"]) => {
    for (const p of ps) {
      const before = powers[p.targetSeat][p.targetPos];
      if (p.action.kind === "power") powers[p.targetSeat][p.targetPos] += p.amount;
      else if (p.action.kind === "silence") silenced[p.targetSeat][p.targetPos] = true;
      else sealed[p.targetSeat][p.targetPos] = true;
      if (input.recordTrace !== false && (p.amount !== 0 || p.action.kind !== "power")) trace.push({ sourceId: p.sourceId, seat: p.ctx.seat, pos: p.ctx.pos, targetSeat: p.targetSeat, targetPos: p.targetPos, before, after: powers[p.targetSeat][p.targetPos], text: p.text, stage });
    }
  };
  apply(contexts().flatMap(c => [arena, ...effects].flatMap(a => makePackets(a, c))), "environment");
  environment = powers.map(p => [...p]);
  const controlContexts = contexts();
  apply(controlContexts.filter(c => !c.silenced[c.seat][c.pos]).flatMap(c => makePackets(characterById(slots[c.seat][c.pos].effectId), c)).filter(p => p.action.kind !== "power"), "control");
  apply(contexts().filter(c => !c.silenced[c.seat][c.pos]).flatMap(c => makePackets(characterById(slots[c.seat][c.pos].effectId), c)).filter(p => p.action.kind === "power"), "character");
  apply(contexts().filter(c => !c.sealed[c.seat][c.pos] && !!slots[c.seat][c.pos].equipment).flatMap(c => { const e = slots[c.seat][c.pos].equipment!; return makePackets(equipmentById(e.id, e.tier), c); }), "equipment");
  powers.forEach(t => t.forEach((v, i) => { t[i] = Math.max(0, Math.floor(v)); }));
  const lineWinners = [0, 1, 2].map(i => powers[0][i] === powers[1][i] ? null : powers[0][i] > powers[1][i] ? 0 : 1) as (NumericSeat | null)[];
  function metric(m: ScoreMetric, seat: NumericSeat): number {
    const win = [0, 1, 2].filter(p => lineWinners[p] === seat);
    switch (m) {
      case "wins": return win.length;
      case "sum": return total(powers[seat]);
      case "centerWin": return Number(lineWinners[1] === seat);
      case "edgeWins": return win.filter(p => p !== 1).length;
      case "upsets": return win.filter(p => slots[seat][p].number < slots[other(seat)][p].number).length;
      case "silentWins": return win.filter(p => silenced[seat][p]).length;
      case "minPower": return Math.min(...powers[seat]);
      case "maxPower": return Math.max(...powers[seat]);
      case "cappedMargins": return total(win.map(p => Math.min(3, powers[seat][p] - powers[other(seat)][p])));
    }
  }
  const scoreVectors = ([0, 1] as NumericSeat[]).map(s => victoryRule.metrics.map(m => metric(m, s))) as [number[], number[]];
  let winner: NumericSeat | null = null;
  for (let i = 0; i < victoryRule.metrics.length; i++) { const diff = scoreVectors[0][i] - scoreVectors[1][i]; if (diff !== 0) { winner = diff > 0 ? 0 : 1; break; } }
  const scores: [number, number] = [scoreVectors[0][0], scoreVectors[1][0]];
  const lines = [0, 1, 2].map(i => `${i + 1}号位：${powers[0][i]} 对 ${powers[1][i]}，${lineWinners[i] === null ? "平局" : `${lineWinners[i] === 0 ? "玩家" : "对手"}赢线`}`);
  lines.push(`${victoryRule.name}：${victoryRule.metrics.map((m, i) => `${SCORE_TEXT[m]} ${scoreVectors[0][i]}:${scoreVectors[1][i]}`).join("；")}。${winner === null ? "完全相同，奖池平分" : `${winner === 0 ? "玩家" : "对手"}获胜`}。`);
  return { winner, powers, lineWinners, lines, scores, scoreVectors, trace, silenced, sealed, teams };
}

/** Public rules shared by tutorial and replay; no card has a private second description. */
export const NUMERIC_SETTLEMENT_TEXT = "原始数字范围3～10；低=3～4，中=5～7，高=8～10。位置固定1对1、2对2、3对3。场地及已启用效果同时修正→锁定人物沉默/装备封印→未沉默人物力量效果→未封印装备力量效果→最终力量最低为0→对位比较→按胜利规则依次比较。沉默只影响人物，封印只影响装备；已锁定的控制不被同阶段沉默撤销。左右指相邻位置，越界时不存在、不提供任何收益；并列最高/最低均满足条件。所有除法向下取整。";
