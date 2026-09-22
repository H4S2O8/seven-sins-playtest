/** Finite, typed numeric rules. No engine dependency and no hidden tie-break. */
// Catalog data only; catalog does not import rules or engine. IDs are never invented.
import { ATTRIBUTES, KEYWORDS, STATUSES } from './catalog.js';
const EFFECTS = { attribute: ATTRIBUTES, keyword: KEYWORDS, status: STATUSES };
const POS = ['上', '右', '下', '左', '中'];
const XY = [[0, -1], [1, 0], [0, 1], [-1, 0], [0, 0]];
export const MAX_RULE_DEPTH = 3;
const MAX_NODES = 7;
const MAX_NUMBER = 1_000_000;
const definitions = [
  ['sum', '数字总和', 1],
  ['max', '最大数字', 1],
  ['min', '最小数字', 1],
  ['spread', '最大最小之差', 2],
  ['absSum', '绝对值总和', 1],
  ['positiveCount', '正数数量', 1],
  ['negativeCount', '负数数量', 1],
  ['evenCount', '偶数数量', 1],
  ['thresholdCount', '达标数量', 1],
  ['distinctCount', '不同数字数量', 2],
  ['adjacentGap', '相邻差距', 2],
  ['oppositeGap', '对位差距', 2],
  ['centerContrast', '中心与外围差', 2],
  ['positionCompare', '两位比较', 2],
  ['ascendingPairs', '顺序递增对数', 2],
  ['descendingPairs', '顺序递减对数', 2],
  ['localPeaks', '局部高点数量', 2],
  ['targetDistance', '逐位目标距离', 1],
  ['rangeCount', '区间内数量', 1],
  ['alternatingSum', '交替加减', 2],
  ['rankWeighted', '排序加权和', 2],
  ['squaredSum', '平方总和', 1],
  ['pairProduct', '两两乘积和', 2],
  ['oddCount', '奇数数量', 1],
  ['stateBonus', '状态奖励总和', 1],
  ['stateWeighted', '条件加权总和', 1],
  ['filteredCount', '组合条件计数', 1],
  ['relationCount', '位置关系条件计数', 2],
];
const DUEL_METRICS = ['duelLarger', 'duelSmaller', 'duelCloser'];
const NUMERIC_FAMILIES = definitions.map(([id, name, minSlots]) =>
  Object.freeze({ id, name, minSlots, numericBaseline: true }));
export const RULE_FAMILIES = Object.freeze([...NUMERIC_FAMILIES,
  ...[['duelLarger', '逐位比大'], ['duelSmaller', '逐位比小'], ['duelCloser', '逐位比目标距离']]
    .map(([id, name]) => Object.freeze({ id, name, minSlots: 1, numericBaseline: true, requiresOpponent: true })),
]);
const FAMILY = new Map(RULE_FAMILIES.map(f => [f.id, f]));
const SCOPES = [
  [0, 1, 2, 3, 4], [0, 1, 2, 3], [0, 4, 2], [3, 4, 1],
  [0, 2], [3, 1], [0, 4], [1, 4], [2, 4], [3, 4],
  [0, 1, 4], [1, 2, 4], [2, 3, 4], [3, 0, 4],
  [0], [1], [2], [3], [4],
];
const serials = new WeakMap();
const betSerials = new WeakMap();
const sum = xs => xs.reduce((a, b) => a + b, 0);
const integer = (x, min, max) => Number.isInteger(x) && x >= min && x <= max;
const record = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const own = (x, k) => Object.prototype.hasOwnProperty.call(x, k);
const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
const positionList = scope => scope.map(i => POS[i]).join('、');
function pairs(scope, predicate = () => true) {
  const result = [];
  for (let i = 0; i < scope.length; i++) for (let j = i + 1; j < scope.length; j++) {
    if (predicate(scope[i], scope[j])) result.push([scope[i], scope[j]]);
  }
  return result;
}
const adjacent = (a, b) => Math.abs(XY[a][0] - XY[b][0]) + Math.abs(XY[a][1] - XY[b][1]) === 1;
const opposite = (a, b) => a !== 4 && b !== 4 && Math.abs(a - b) === 2;
function suitable(metric, scope) {
  if (scope.length < FAMILY.get(metric).minSlots) return false;
  if (metric === 'positionCompare') return scope.length === 2;
  if (metric === 'adjacentGap' || metric === 'localPeaks') return pairs(scope, adjacent).length > 0;
  if (metric === 'oppositeGap') return pairs(scope, opposite).length > 0;
  if (metric === 'centerContrast') return scope.includes(4) && scope.length > 1;
  return true;
}
function matches(cell, condition) {
  if (condition.kind === 'all') return condition.conditions.every(c => matches(cell, c));
  if (condition.kind === 'any') return condition.conditions.some(c => matches(cell, c));
  if (condition.kind === 'value') return compare(cell.value, condition.comparison, condition.value);
  if (condition.kind === 'parity') return (Math.abs(cell.value % 2) === 0) === (condition.parity === 'even');
  if (condition.kind === 'attribute') return condition.id === undefined
    ? typeof cell.attribute === 'string' : cell.attribute === condition.id;
  if (condition.kind === 'keyword') return condition.id === undefined
    ? cell.keywords.length > 0 : cell.keywords.includes(condition.id);
  return Object.entries(cell.statuses).some(([id, status]) =>
    (condition.id === undefined || condition.id === id) && status.turns > 0);
}
function compare(a, comparison, b) {
  return comparison === 'gt' ? a > b : comparison === 'lt' ? a < b : comparison === 'gte' ? a >= b : comparison === 'lte' ? a <= b : a === b;
}
function relationPairs(node) {
  return pairs(node.scope, node.relation === 'adjacent' ? adjacent : node.relation === 'opposite' ? opposite : () => true);
}
function conditionErrors(condition) {
  const errors = [], seen = new Set(); let count = 0;
  function visit(c, depth) {
    if (!record(c) || depth > 3 || ++count > 7 || seen.has(c)) { errors.push('条件结构无效或过深'); return; }
    seen.add(c);
    let keys;
    if (c.kind === 'all' || c.kind === 'any') {
      keys = ['kind', 'conditions'];
      if (!Array.isArray(c.conditions) || c.conditions.length !== 2) errors.push('组合条件须有两个子条件');
      else for (const child of c.conditions) visit(child, depth + 1);
    } else if (c.kind === 'value') {
      keys = ['kind', 'comparison', 'value'];
      if (!['gt', 'lt', 'gte', 'lte', 'eq'].includes(c.comparison) || !integer(c.value, -30, 30)) errors.push('数值条件无效');
    } else if (c.kind === 'parity') {
      keys = ['kind', 'parity'];
      if (!['even', 'odd'].includes(c.parity)) errors.push('奇偶条件无效');
    } else {
      keys = ['kind', 'id'];
      if (!['attribute', 'keyword', 'status'].includes(c.kind) || (own(c, 'id') && (typeof c.id !== 'string' || !c.id.length || c.id.length > 100))) errors.push('效果条件无效');
    }
    if (Object.keys(c).some(k => !keys.includes(k))) errors.push('条件有未知字段');
  }
  visit(condition, 1);
  return errors;
}
function metricValue(node, board) {
  const { metric, scope } = node;
  const values = scope.map(i => board.cells[i].value);
  const value = i => board.cells[i].value;
  switch (metric) {
    case 'sum': return sum(values);
    case 'max': return Math.max(...values);
    case 'min': return Math.min(...values);
    case 'spread': return Math.max(...values) - Math.min(...values);
    case 'absSum': return sum(values.map(Math.abs));
    case 'positiveCount': return values.filter(v => v > 0).length;
    case 'negativeCount': return values.filter(v => v < 0).length;
    case 'evenCount': return values.filter(v => v % 2 === 0).length;
    case 'oddCount': return values.filter(v => v % 2 !== 0).length;
    case 'thresholdCount': return values.filter(v => v >= node.threshold).length;
    case 'distinctCount': return new Set(values).size;
    case 'adjacentGap': return sum(pairs(scope, adjacent).map(([a, b]) => Math.abs(value(a) - value(b))));
    case 'oppositeGap': return sum(pairs(scope, opposite).map(([a, b]) => Math.abs(value(a) - value(b))));
    case 'centerContrast': return value(4) * (scope.length - 1) - sum(scope.filter(i => i !== 4).map(value));
    case 'positionCompare': return Math.sign(values[0] - values[1]);
    case 'ascendingPairs': return pairs(scope).filter(([a, b]) => value(a) < value(b)).length;
    case 'descendingPairs': return pairs(scope).filter(([a, b]) => value(a) > value(b)).length;
    case 'localPeaks': return scope.filter(i => {
      const neighbors = scope.filter(j => adjacent(i, j));
      return neighbors.length > 0 && neighbors.every(j => value(i) > value(j));
    }).length;
    case 'targetDistance': return sum(values.map(v => Math.abs(v - node.target)));
    case 'rangeCount': return values.filter(v => v >= node.low && v <= node.high).length;
    case 'alternatingSum': return sum(values.map((v, i) => i % 2 === 0 ? v : -v));
    case 'rankWeighted': return sum([...values].sort((a, b) => a - b).map((v, i) => v * (i + 1)));
    case 'squaredSum': return sum(values.map(v => v * v));
    case 'pairProduct': return sum(pairs(scope).map(([a, b]) => value(a) * value(b)));
    case 'stateBonus': return sum(values) + node.bonus * scope.filter(i => matches(board.cells[i], node.condition)).length;
    case 'stateWeighted': return sum(scope.map(i => value(i) * (matches(board.cells[i], node.condition) ? node.weight : 1)));
    case 'filteredCount': return scope.filter(i => matches(board.cells[i], node.condition)).length;
    case 'relationCount': return relationPairs(node).filter(([a, b]) =>
      matches(board.cells[a], node.leftCondition) && matches(board.cells[b], node.rightCondition) &&
      (node.comparison === 'gapLte' ? Math.abs(value(a) - value(b)) <= node.distance : compare(value(a), node.comparison, value(b)))).length;
    default: throw new TypeError('未知数字指标');
  }
}
function rawValue(node, board) {
  switch (node.type) {
    case 'metric': return metricValue(node, board);
    case 'add': return node.leftWeight * rawValue(node.left, board) + node.rightWeight * rawValue(node.right, board);
    case 'difference': return rawValue(node.left, board) - rawValue(node.right, board);
    case 'distance': return Math.abs(rawValue(node.child, board) - node.target);
    default: throw new TypeError('未知规则节点');
  }
}
const utility = (rule, raw) => {
  const result = rule.mode === 'max' ? raw : rule.mode === 'min' ? -raw : -Math.abs(raw - rule.target);
  return result === 0 ? 0 : result;
};
function assertBoard(board) {
  if (!record(board) || !Array.isArray(board.cells) || board.cells.length !== 5 || !integer(board.turn, 0, Number.MAX_SAFE_INTEGER)) {
    throw new TypeError('棋盘必须包含五个位置和非负整数回合');
  }
  for (const cell of board.cells) {
    if (!record(cell) || !integer(cell.value, -30, 30) || !(cell.attribute === null || typeof cell.attribute === 'string') ||
      !Array.isArray(cell.keywords) || !cell.keywords.every(x => typeof x === 'string') || !record(cell.statuses) ||
      !Object.values(cell.statuses).every(s => record(s) && integer(s.turns, 0, Number.MAX_SAFE_INTEGER))) {
      throw new TypeError('棋盘数字须为 -30 至 30 的整数，属性、关键词和状态须符合契约');
    }
  }
}
function nodeScopes(node) {
  if (node.type === 'metric' || node.type === 'duel') return [...node.scope];
  if (node.type === 'distance') return nodeScopes(node.child);
  return [...new Set([...nodeScopes(node.left), ...nodeScopes(node.right)])];
}
const METRIC_KEYS = {
  thresholdCount: ['threshold'], targetDistance: ['target'], rangeCount: ['low', 'high'],
  stateBonus: ['condition', 'bonus'], stateWeighted: ['condition', 'weight'],
  filteredCount: ['condition'], relationCount: ['relation', 'comparison', 'distance', 'leftCondition', 'rightCondition'],
};
function schemaErrors(rule) {
  const errors = [];
  const fail = text => errors.push(text);
  if (!record(rule)) return ['规则必须是对象'];
  if (typeof rule.id !== 'string' || !rule.id.length || rule.id.length > 200) fail('规则必须有有效 id');
  for (const field of ['title', 'description']) if (typeof rule[field] !== 'string' || !rule[field].trim()) fail(`缺少 ${field}`);
  if (own(rule, 'simple') && typeof rule.simple !== 'boolean') fail('simple 必须为布尔值');
  const isDuel = record(rule.ast) && rule.ast.type === 'duel';
  if (isDuel ? rule.requiresOpponent !== true : own(rule, 'requiresOpponent') && rule.requiresOpponent !== false) fail('逐位对抗必须标记 requiresOpponent:true，单盘规则不得标记为对抗');
  if (isDuel && rule.mode !== 'max') fail('逐位对抗始终比较赢下的位置数，mode 必须为 max');
  if (!['max', 'min', 'target'].includes(rule.mode)) fail('未知胜负模式');
  if (rule.mode === 'target' ? !integer(rule.target, -MAX_NUMBER, MAX_NUMBER) : own(rule, 'target')) fail('目标模式须有整数目标，其他模式不得携带目标');
  const validScope = s => Array.isArray(s) && s.length >= 1 && s.length <= 5 && Array.from(s).every(i => integer(i, 0, 4)) && new Set(s).size === s.length;
  if (!validScope(rule.scope)) fail('位置须为互不重复的 0 至 4');
  let count = 0;
  const seen = new Set();
  function visit(node, depth) {
    if (!record(node) || depth > MAX_RULE_DEPTH || ++count > MAX_NODES || seen.has(node)) { fail('节点无效、循环或超过深度/数量限制'); return; }
    seen.add(node);
    const allowed = (keys) => { if (Object.keys(node).some(k => !keys.includes(k))) fail('节点包含未知字段'); };
    if (node.type === 'metric') {
      allowed(['type', 'metric', 'scope', ...(own(METRIC_KEYS, node.metric) ? METRIC_KEYS[node.metric] : [])]);
      if (!FAMILY.has(node.metric) || DUEL_METRICS.includes(node.metric)) { fail('未知单盘数字指标'); return; }
      if (!validScope(node.scope) || !suitable(node.metric, node.scope)) { fail('指标位置不适用'); return; }
      if (node.metric === 'thresholdCount' && !integer(node.threshold, -29, 30)) fail('阈值必须可跨越');
      if (node.metric === 'targetDistance' && !integer(node.target, -30, 30)) fail('逐位目标超出数字范围');
      if (node.metric === 'rangeCount' && (!integer(node.low, -30, 30) || !integer(node.high, -30, 30) || node.low > node.high || (node.low === -30 && node.high === 30))) fail('区间必须可命中且可离开');
      if (['stateBonus', 'stateWeighted', 'filteredCount'].includes(node.metric)) {
        errors.push(...conditionErrors(node.condition));
        if (node.metric === 'stateBonus' && !integer(node.bonus, 1, 9)) fail('状态奖励须为 1 至 9');
        if (node.metric === 'stateWeighted' && !integer(node.weight, 2, 4)) fail('状态权重须为 2 至 4');
      }
      if (node.metric === 'relationCount') {
        errors.push(...conditionErrors(node.leftCondition), ...conditionErrors(node.rightCondition));
        if (!['all', 'adjacent', 'opposite'].includes(node.relation) || relationPairs(node).length === 0) fail('位置关系没有可比较的位置对');
        if (!['gt', 'lt', 'eq', 'gapLte'].includes(node.comparison)) fail('位置比较无效');
        if (node.comparison === 'gapLte' ? !integer(node.distance, 0, 59) : own(node, 'distance')) fail('位置距离参数无效');
      }
    } else if (node.type === 'duel') {
      allowed(['type', 'metric', 'scope', ...(node.metric === 'duelCloser' ? ['target'] : [])]);
      if (depth !== 1) fail('逐位对抗只能作为根节点，不能嵌入单盘算式');
      if (!DUEL_METRICS.includes(node.metric)) fail('未知逐位对抗指标');
      if (!validScope(node.scope)) fail('逐位对抗位置无效');
      if (node.metric === 'duelCloser' && !integer(node.target, -30, 30)) fail('逐位对抗目标须为 -30 至 30 的可达整数');
    } else if (node.type === 'add' || node.type === 'difference') {
      allowed(['type', 'left', 'right', ...(node.type === 'add' ? ['leftWeight', 'rightWeight'] : [])]);
      if (node.type === 'add' && (!integer(node.leftWeight, 1, 3) || !integer(node.rightWeight, 1, 3))) fail('组合权重须为 1 至 3');
      visit(node.left, depth + 1); visit(node.right, depth + 1);
    } else if (node.type === 'distance') {
      allowed(['type', 'child', 'target']);
      if (!integer(node.target, -MAX_NUMBER, MAX_NUMBER)) fail('距离目标无效');
      visit(node.child, depth + 1);
    } else fail('未知 AST 节点类型');
  }
  visit(rule.ast, 1);
  if (errors.length === 0) {
    if (!same([...rule.scope].sort(), nodeScopes(rule.ast).sort())) fail('规则位置必须准确覆盖计算位置');
    if (rule.metric !== (rule.ast.type === 'metric' || isDuel ? rule.ast.metric : 'composite')) fail('metric 与 AST 不一致');
  }
  return errors;
}
function assertRule(rule) {
  const errors = schemaErrors(rule);
  if (errors.length) throw new TypeError(`规则无效：${errors.join('；')}`);
}
/**
 * Single-board rules: exact comparison score, larger is better.
 * requiresOpponent rules: heuristic ONLY, never a position-win count:
 * larger=sum, smaller=-sum, closer=-sum(abs(value-target)), restricted to scope.
 * UI must hide its single-board score indicator for requiresOpponent:true.
 */
export function scoreBoard(rule, board) {
  assertRule(rule); assertBoard(board);
  if (rule.requiresOpponent) {
    const node = rule.ast;
    const values = node.scope.map(i => board.cells[i].value);
    const result = node.metric === 'duelLarger' ? sum(values) : node.metric === 'duelSmaller'
      ? -sum(values) : -sum(values.map(v => Math.abs(v - node.target)));
    return result === 0 ? 0 : result;
  }
  const result = utility(rule, rawValue(rule.ast, board));
  return result === 0 ? 0 : result;
}
function conditionText(c) {
  if (c.kind === 'all' || c.kind === 'any') return `（${c.conditions.map(conditionText).join(c.kind === 'all' ? '且' : '或')}）`;
  if (c.kind === 'value') return `数字${{ gt: '大于', lt: '小于', gte: '大于等于', lte: '小于等于', eq: '等于' }[c.comparison]} ${c.value}`;
  if (c.kind === 'parity') return `数字为${c.parity === 'even' ? '偶数（含零及负偶数）' : '奇数（含负奇数）'}`;
  const kind = { attribute: '属性', keyword: '关键词', status: '有效状态（剩余回合大于零）' }[c.kind];
  return c.id === undefined ? `带任意${kind}` : `带${kind}「${EFFECTS[c.kind].find(e => e.id === c.id)?.name ?? c.id}」`;
}
function expression(node) {
  if (node.type === 'add') return `（${node.leftWeight}×［${expression(node.left)}］＋${node.rightWeight}×［${expression(node.right)}］）`;
  if (node.type === 'difference') return `（［${expression(node.left)}］－［${expression(node.right)}］）`;
  if (node.type === 'distance') return `［${expression(node.child)}］与 ${node.target} 的绝对差`;
  const s = `【${positionList(node.scope)}】`;
  const pairText = predicate => pairs(node.scope, predicate).map(([a, b]) => `${POS[a]}↔${POS[b]}`).join('、');
  switch (node.metric) {
    case 'sum': return `${s}数字相加`;
    case 'max': return `${s}中最大的数字`;
    case 'min': return `${s}中最小的数字`;
    case 'spread': return `${s}最大数字减最小数字`;
    case 'absSum': return `${s}每个数字的绝对值相加`;
    case 'positiveCount': return `${s}大于 0 的位置数`;
    case 'negativeCount': return `${s}小于 0 的位置数`;
    case 'evenCount': return `${s}偶数的位置数（0 和负偶数也算）`;
    case 'oddCount': return `${s}奇数的位置数（负奇数也算）`;
    case 'thresholdCount': return `${s}数字大于等于 ${node.threshold} 的位置数`;
    case 'distinctCount': return `${s}互不相同的数字种类数`;
    case 'adjacentGap': return `${s}相邻对（${pairText(adjacent)}）的数字绝对差之和，每对只算一次`;
    case 'oppositeGap': return `${s}对位对（${pairText(opposite)}）的数字绝对差之和，每对只算一次`;
    case 'centerContrast': return `${s}中心数字×${node.scope.length - 1}，再减去所选外围数字之和`;
    case 'positionCompare': return `比较${POS[node.scope[0]]}与${POS[node.scope[1]]}：前者较大记 1，相等记 0，较小记 -1`;
    case 'ascendingPairs': return `${s}按此顺序取所有前后位置对，前数严格小于后数的对数（不只相邻对）`;
    case 'descendingPairs': return `${s}按此顺序取所有前后位置对，前数严格大于后数的对数（不只相邻对）`;
    case 'localPeaks': return `${s}严格大于全部所选相邻位置的位置数（相邻指中心与外围；孤立位置不计）`;
    case 'targetDistance': return `${s}每个数字与 ${node.target} 的绝对差相加`;
    case 'rangeCount': return `${s}数字在 ${node.low} 至 ${node.high} 内的位置数（包含两端）`;
    case 'alternatingSum': return `${s}按此顺序依次加、减、加、减、加（只算所选位置）`;
    case 'rankWeighted': return `${s}数字从小到大排序，依次乘 1 至 ${node.scope.length} 后相加（相同数字也各占一位）`;
    case 'squaredSum': return `${s}每个数字的平方相加`;
    case 'pairProduct': return `${s}任意两个不同位置的数字相乘，再将全部乘积相加，每对只算一次`;
    case 'stateBonus': return `${s}数字总和，加上每个${conditionText(node.condition)}的位置奖励 ${node.bonus}（每位最多一次）`;
    case 'stateWeighted': return `${s}各位数字相加，其中${conditionText(node.condition)}的位置数字先乘 ${node.weight}，其余乘 1`;
    case 'filteredCount': return `${s}满足${conditionText(node.condition)}的位置数`;
    case 'relationCount': return `${s}按所列顺序取位置对（${relationPairs(node).map(([a, b]) => `${POS[a]}→${POS[b]}`).join('、')}），前位满足${conditionText(node.leftCondition)}、后位满足${conditionText(node.rightCondition)}，且${node.comparison === 'gapLte' ? `两数绝对差不超过 ${node.distance}` : `前数${{ gt: '大于', lt: '小于', eq: '等于' }[node.comparison]}后数`}的对数，每对只算一次`;
    default: throw new TypeError('未知数字指标');
  }
}
function description(rule) {
  if (rule.requiresOpponent) {
    const contest = rule.metric === 'duelLarger' ? '数字严格较大' : rule.metric === 'duelSmaller' ? '数字严格较小' : `数字与目标 ${rule.ast.target} 的绝对差严格较小`;
    return `${rule.simple ? '新手说明：' : ''}双方在【${positionList(rule.ast.scope)}】的相同位置逐一对抗，每位${contest}的一方赢下该位并得 1 分；${rule.metric === 'duelCloser' ? '距离相等' : '数字相等'}时该位中立，双方均不得分。赢下的位置数较多者获胜，不比较数字总和或差距大小；赢位数相同就是平局，返还双方主注，不追加任何胜负条件。`;
  }
  const goal = rule.mode === 'max' ? '计算结果较大者获胜' : rule.mode === 'min' ? '计算结果较小者获胜' : `计算结果与目标 ${rule.target} 的绝对差较小者获胜`;
  return `${rule.simple ? '新手说明：双方分别计算自己的盘面。' : ''}${expression(rule.ast)}。${goal}；${rule.mode === 'target' ? '与目标的距离相同' : '结果相同'}就是平局，返还双方主注，不追加任何胜负条件。`;
}
/** Derive text from executable data, never trust a stale saved description. */
export function describeRule(rule) { assertRule(rule); return description(rule); }
function trace(node, board) {
  if (node.type === 'metric') {
    const matched = node.condition ? `；满足条件的位置［${node.scope.filter(i => matches(board.cells[i], node.condition)).map(i => POS[i]).join('、') || '无'}］` : '';
    return `${expression(node)}；所选数字［${node.scope.map(i => `${POS[i]}=${board.cells[i].value}`).join('，')}］${matched}；计算值=${rawValue(node, board)}`;
  }
  if (node.type === 'distance') return `子项［${trace(node.child, board)}］；绝对差 |${rawValue(node.child, board)}－${node.target}|=${rawValue(node, board)}`;
  return `左项［${trace(node.left, board)}］；右项［${trace(node.right, board)}］；${node.type === 'add' ? `${node.leftWeight}×左项＋${node.rightWeight}×右项` : '左项－右项'}=${rawValue(node, board)}`;
}
export function evaluateRule(rule, boardA, boardB) {
  assertRule(rule); assertBoard(boardA); assertBoard(boardB);
  if (rule.requiresOpponent) return evaluateDuel(rule, boardA, boardB);
  const boards = [boardA, boardB];
  const raws = boards.map(board => rawValue(rule.ast, board));
  const scores = raws.map(raw => utility(rule, raw)).map(v => v === 0 ? 0 : v);
  const winner = scores[0] === scores[1] ? null : scores[0] > scores[1] ? 0 : 1;
  const details = boards.map((board, i) => `${trace(rule.ast, board)}。${rule.mode === 'target' ? `距目标 ${rule.target} 的距离=${Math.abs(raws[i] - rule.target)}；` : ''}比较分=${scores[i]}（越高越有利${rule.mode === 'min' ? '，计算值取负数' : rule.mode === 'target' ? '，目标距离取负数' : ''}）。`);
  const reason = winner === null ? '平局：双方比较分相同，返还双方主注；不追加胜负条件。' : `${winner === 0 ? '甲方' : '乙方'}获胜：比较分 ${scores[winner]} 高于 ${scores[1 - winner]}。`;
  return { winner, scores, details, reason };
}
function duelPositions(node, boardA, boardB) {
  return node.scope.map(index => {
    const a = boardA.cells[index].value, b = boardB.cells[index].value;
    const delta = node.metric === 'duelCloser' ? Math.abs(b - node.target) - Math.abs(a - node.target)
      : node.metric === 'duelSmaller' ? b - a : a - b;
    return { index, values: [a, b], winner: delta === 0 ? null : delta > 0 ? 0 : 1 };
  });
}
function evaluateDuel(rule, boardA, boardB) {
  const positions = duelPositions(rule.ast, boardA, boardB);
  const scores = [0, 0];
  positions.forEach(p => { if (p.winner !== null) scores[p.winner]++; });
  const winner = scores[0] === scores[1] ? null : scores[0] > scores[1] ? 0 : 1;
  // Own-relative wording makes the details swap exactly when players swap.
  const details = [0, 1].map(side => positions.map(p => {
    const a = p.values[side], b = p.values[1 - side];
    const arithmetic = rule.metric === 'duelCloser'
      ? `本方 |${a}－（${rule.ast.target}）|=${Math.abs(a - rule.ast.target)}，对方 |${b}－（${rule.ast.target}）|=${Math.abs(b - rule.ast.target)}，距离较小者赢位`
      : `本方 ${a}－对方（${b}）=${a - b}，${rule.metric === 'duelLarger' ? '正差赢位、负差失位' : '负差赢位、正差失位'}`;
    const outcome = p.winner === null ? '相等，中立（双方 +0）' : p.winner === side ? '本方赢位（本方 +1，对方 +0）' : '对方赢位（本方 +0，对方 +1）';
    return `${POS[p.index]}：${arithmetic}；${outcome}`;
  }).join('。') + `。本方赢位数=${scores[side]}，对方赢位数=${scores[1 - side]}；中立位置数=${positions.length - scores[0] - scores[1]}。`);
  const reason = winner === null ? `平局：双方均赢下 ${scores[0]} 个位置，返还双方主注；中立位置不得分，不追加胜负条件。`
    : `${winner === 0 ? '甲方' : '乙方'}获胜：赢下 ${scores[winner]} 个位置，多于对方的 ${scores[1 - winner]} 个位置；中立位置不得分。`;
  return { winner, scores, details, reason };
}
function seeded(seed) {
  let state = typeof seed === 'number' && Number.isFinite(seed) ? seed >>> 0 : 2166136261;
  if (typeof seed !== 'number') for (const c of String(seed)) state = Math.imul(state ^ c.charCodeAt(0), 16777619) >>> 0;
  return () => {
    state = (state + 0x6D2B79F5) >>> 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t ^= t + Math.imul(t ^ (t >>> 7), 61 | t);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
const makeWitness = values => ({ cells: values.map(value => ({ value, attribute: null, keywords: [], statuses: {} })), turn: 0 });
const OPENING_WITNESSES = [];
const NUMERIC_WITNESSES = [];
for (let v = -30; v <= 30; v++) NUMERIC_WITNESSES.push(makeWitness(Array(5).fill(v)));
for (let v = 0; v <= 9; v++) OPENING_WITNESSES.push(makeWitness(Array(5).fill(v)));
const witnessRandom = seeded(230923);
for (let k = 0; k < 64; k++) {
  NUMERIC_WITNESSES.push(makeWitness(Array.from({ length: 5 }, () => Math.floor(witnessRandom() * 61) - 30)));
  OPENING_WITNESSES.push(makeWitness(Array.from({ length: 5 }, () => Math.floor(witnessRandom() * 10))));
}
function conditions(node) {
  if (node.type === 'metric') return [node.condition, node.leftCondition, node.rightCondition].filter(Boolean);
  if (node.type === 'distance') return conditions(node.child);
  return [...conditions(node.left), ...conditions(node.right)];
}
function atoms(condition) {
  return condition.conditions ? condition.conditions.flatMap(atoms) : [condition];
}
function installConditions(board, filters, mask = 31) {
  for (const c of filters.flatMap(atoms)) {
    const id = c.id ?? 'witness';
    board.cells.forEach((cell, i) => {
      if (!(mask & (1 << i))) return;
      if (c.kind === 'attribute') cell.attribute = id;
      if (c.kind === 'keyword' && !cell.keywords.includes(id)) cell.keywords.push(id);
      if (c.kind === 'status') cell.statuses[id] = { turns: 2 };
    });
  }
}
function witnessBoards(ast) {
  const boards = [...OPENING_WITNESSES, ...NUMERIC_WITNESSES];
  const filters = conditions(ast);
  for (const condition of filters.flatMap(atoms).filter(c => ['attribute', 'keyword', 'status'].includes(c.kind))) {
    for (const mask of [1, 2, 4, 8, 16, 21, 31]) {
      const board = makeWitness([2, 5, -3, 8, 1]);
      const id = condition.id ?? 'witness';
      board.cells.forEach((cell, i) => {
        if (!(mask & (1 << i))) return;
        if (condition.kind === 'attribute') cell.attribute = id;
        else if (condition.kind === 'keyword') cell.keywords.push(id);
        else cell.statuses = { [id]: { turns: 2 } };
      });
      boards.push(board);
    }
  }
  if (filters.length) {
    // Joint-effect witnesses, including opposing attributes on different cells.
    for (const numeric of NUMERIC_WITNESSES.slice(0, 61)) {
      const b = structuredClone(numeric); installConditions(b, filters); boards.push(b);
    }
    for (const mask of [1, 2, 4, 8, 16, 21, 31]) {
      for (const values of [[0, 2, 4, 6, 8], [9, 7, 5, 3, 1], [-30, 30, -9, 9, 0]]) {
        const b = makeWitness(values);
        installConditions(b, filters.slice(0, 1), mask);
        installConditions(b, filters.slice(1), 31 ^ mask);
        boards.push(b);
      }
    }
  }
  return boards;
}
function distanceNodes(node) {
  if (node.type === 'metric') return [];
  if (node.type === 'distance') return [node, ...distanceNodes(node.child)];
  return [...distanceNodes(node.left), ...distanceNodes(node.right)];
}
/** Returns {valid, errors, witnesses?}. Validation is conservative, witness-backed. */
export function validateRule(rule) {
  const errors = schemaErrors(rule);
  if (errors.length) return { valid: false, errors };
  if (rule.requiresOpponent) {
    // Prove meaningful pair outcomes on legal, plain 0..9 opening boards,
    // rather than confusing the single-board heuristic with the real score.
    const low = makeWitness([0, 0, 0, 0, 0]), high = makeWitness([9, 9, 9, 9, 9]);
    const pairs = [[low, high], [high, low], [low, structuredClone(low)]];
    if (rule.metric === 'duelCloser') {
      const target = rule.ast.target;
      pairs.push([makeWitness(Array(5).fill(target)), makeWitness(Array(5).fill(target === 30 ? 29 : target + 1))]);
    }
    const pairWitnesses = pairs.map(boards => {
      const { winner, scores } = evaluateDuel(rule, ...boards);
      return { boards, winner, scores };
    });
    if (![0, 1, null].every(outcome => pairWitnesses.slice(0, 3).some(w => w.winner === outcome))) errors.push('逐位对抗缺少双方获胜及平局的开局见证');
    return errors.length ? { valid: false, errors } : { valid: true, errors: [], pairWitnesses };
  }
  const boards = witnessBoards(rule.ast);
  const raw = boards.map(board => rawValue(rule.ast, board));
  const scored = raw.map(v => utility(rule, v));
  if (!raw.every(Number.isFinite) || !scored.every(Number.isFinite)) errors.push('计算必须有限');
  if (new Set(scored).size < 2) errors.push('未找到不同胜负分的见证棋盘');
  if (new Set(OPENING_WITNESSES.map(board => utility(rule, rawValue(rule.ast, board)))).size < 2) errors.push('无属性的 0 至 9 开局必须有数字差异');
  if (rule.mode === 'target' && !raw.includes(rule.target)) errors.push('目标必须有可达见证');
  for (const node of distanceNodes(rule.ast)) {
    if (!boards.some(board => rawValue(node.child, board) === node.target)) errors.push('组合距离目标必须有可达见证');
  }
  if (errors.length) return { valid: false, errors };
  const low = scored.indexOf(Math.min(...scored)), high = scored.indexOf(Math.max(...scored));
  // Return independent witnesses; callers cannot mutate future validation inputs.
  return { valid: true, errors: [], witnesses: [low, high].map(i => ({ board: structuredClone(boards[i]), raw: raw[i], score: scored[i] })) };
}
function draw(random) {
  const n = random();
  if (typeof n !== 'number' || !Number.isFinite(n) || n < 0 || n >= 1) throw new TypeError('random 必须返回 [0,1) 内的有限数字');
  return n;
}
const pick = (random, xs) => xs[Math.floor(draw(random) * xs.length)];
const randomInt = (random, low, high) => low + Math.floor(draw(random) * (high - low + 1));
const ALL_SCOPES = Array.from({ length: 31 }, (_, n) => [0, 1, 2, 3, 4].filter(i => (n + 1) & (1 << i)));
function randomScope(random, metric, simple = false) {
  const scope = [...pick(random, ALL_SCOPES.filter(s => (!metric || suitable(metric, s)) && (!simple || s.length >= 2)))];
  for (let i = scope.length - 1; i > 0; i--) {
    const j = randomInt(random, 0, i); [scope[i], scope[j]] = [scope[j], scope[i]];
  }
  return scope;
}
function randomCondition(random) {
  const effect = kind => ({ kind, id: pick(random, EFFECTS[kind]).id });
  const numeric = () => draw(random) < 0.4 ? { kind: 'parity', parity: pick(random, ['even', 'odd']) }
    : { kind: 'value', comparison: pick(random, ['gte', 'lte', 'eq']), value: randomInt(random, -9, 9) };
  const kind = pick(random, ['attribute', 'keyword', 'status']);
  const first = effect(kind);
  const form = randomInt(random, 0, 4);
  if (form === 0) return first;
  if (form === 1) return numeric();
  const second = form === 2 ? effect(pick(random, ['attribute', 'keyword', 'status'].filter(k => k !== kind))) : numeric();
  return { kind: pick(random, ['all', 'any']), conditions: [first, second] };
}
function makeLeaf(random, forcedMetric, simple = false) {
  const metric = forcedMetric ?? pick(random, NUMERIC_FAMILIES).id;
  const scope = randomScope(random, metric, simple);
  const leaf = { type: 'metric', metric, scope };
  if (metric === 'thresholdCount') leaf.threshold = randomInt(random, 1, 9);
  if (metric === 'targetDistance') leaf.target = randomInt(random, -9, 9);
  if (metric === 'rangeCount') {
    leaf.low = pick(random, [0, 1, 2, 3, 4, 5]);
    leaf.high = leaf.low + pick(random, [1, 2, 3, 4]);
  }
  if (['stateBonus', 'stateWeighted', 'filteredCount'].includes(metric)) {
    leaf.condition = randomCondition(random);
    if (metric === 'stateBonus') leaf.bonus = randomInt(random, 1, 9);
    else leaf.weight = pick(random, [2, 3, 4]);
    if (metric === 'filteredCount') delete leaf.weight;
  }
  if (metric === 'relationCount') {
    leaf.relation = pick(random, ['all', 'adjacent', 'opposite'].filter(relation => relationPairs({ scope, relation }).length));
    leaf.comparison = pick(random, ['gt', 'lt', 'eq', 'gapLte']);
    if (leaf.comparison === 'gapLte') leaf.distance = randomInt(random, 0, 15);
    leaf.leftCondition = randomCondition(random); leaf.rightCondition = randomCondition(random);
  }
  return leaf;
}
function makeAst(random) {
  const leaf = makeLeaf(random);
  const form = pick(random, ['leaf', 'leaf', 'leaf', 'add', 'difference', 'distance', 'distanceAdd']);
  if (form === 'leaf') return leaf;
  let ast = leaf;
  if (form === 'add' || form === 'difference' || form === 'distanceAdd') {
    ast = { type: form === 'difference' ? 'difference' : 'add', left: leaf, right: makeLeaf(random) };
    if (ast.type === 'add') { ast.leftWeight = pick(random, [1, 2, 3]); ast.rightWeight = pick(random, [1, 2, 3]); }
  }
  if (form === 'distance' || form === 'distanceAdd') ast = { type: 'distance', child: ast, target: rawValue(ast, pick(random, OPENING_WITNESSES)) };
  return ast;
}
function finishRule(ast, mode, target, simple) {
  const rule = { id: 'pending', title: ast.type === 'metric' ? FAMILY.get(ast.metric).name : '组合数字挑战', description: '待生成',
    scope: nodeScopes(ast), metric: ast.type === 'metric' ? ast.metric : 'composite', mode, ast, simple };
  if (mode === 'target') rule.target = target;
  rule.description = description(rule);
  return rule;
}
function finishDuel(metric, scope, target, simple = false) {
  const ast = { type: 'duel', metric, scope: [...scope] };
  if (metric === 'duelCloser') ast.target = target;
  const rule = { id: 'pending', title: FAMILY.get(metric).name, description: '待生成',
    scope: [...scope], metric, mode: 'max', ast, simple, requiresOpponent: true };
  rule.description = description(rule);
  return rule;
}
/** Simple rules deliberately avoid status conditions and nested calculations. */
export function generateRule(random = Math.random, { simple = false } = {}) {
  if (typeof random !== 'function' || typeof simple !== 'boolean') throw new TypeError('生成器参数无效');
  let rule;
  for (let attempt = 0; attempt < 24; attempt++) {
    if (!simple && draw(random) < 0.18) {
      rule = finishDuel(pick(random, DUEL_METRICS), randomScope(random), randomInt(random, -9, 9));
      if (validateRule(rule).valid) break;
      rule = undefined;
      continue;
    }
    const ast = simple ? makeLeaf(random, pick(random, ['sum', 'max', 'min', 'spread']), true) : makeAst(random);
    // A negative-count leaf alone has no opening variation; pair it with the numeric sum.
    if (!simple && ast.type === 'metric' && ['negativeCount', 'filteredCount', 'relationCount'].includes(ast.metric)) {
      const base = { type: 'metric', metric: 'sum', scope: [...ast.scope] };
      rule = finishRule({ type: 'add', left: base, right: ast, leftWeight: 1, rightWeight: 3 }, pick(random, ['max', 'min']), undefined, false);
    } else {
      const mode = pick(random, simple ? ['max', 'min'] : ['max', 'min', 'target']);
      const target = mode === 'target' ? rawValue(ast, pick(random, OPENING_WITNESSES)) : undefined;
      rule = finishRule(ast, mode, target, simple);
    }
    if (validateRule(rule).valid) break;
    rule = undefined;
  }
  if (!rule) rule = finishRule({ type: 'metric', metric: 'sum', scope: [0, 1, 2, 3, 4] }, 'max', undefined, simple);
  const serial = (serials.get(random) ?? 0) + 1;
  serials.set(random, serial);
  rule.id = `rule-${serial.toString(36)}-${Math.floor(draw(random) * 4294967296).toString(36)}-${Math.floor(draw(random) * 4294967296).toString(36)}`;
  return rule;
}
function freezeTree(value) {
  if (value && typeof value === 'object') {
    Object.values(value).forEach(freezeTree);
    Object.freeze(value);
  }
  return value;
}
/** Guaranteed tutorial choices. Index 0: sum all five numbers, larger wins. */
export const SIMPLE_RULES = freezeTree([
  { ...finishRule({ type: 'metric', metric: 'sum', scope: [0, 1, 2, 3, 4] }, 'max', undefined, true), id: 'tutorial-five-sum-max', title: '五位总和较大获胜' },
  { ...finishRule({ type: 'metric', metric: 'sum', scope: [0, 1, 2, 3, 4] }, 'min', undefined, true), id: 'tutorial-five-sum-min', title: '五位总和较小获胜' },
  { ...finishRule({ type: 'metric', metric: 'spread', scope: [0, 1, 2, 3, 4] }, 'min', undefined, true), id: 'tutorial-five-spread-min', title: '五位数字越接近越好' },
]);
/** Literal tutorial: compare all five matching slots; larger wins each slot. */
export const DUEL_TUTORIAL_RULE = freezeTree({
  ...finishDuel('duelLarger', [0, 1, 2, 3, 4], undefined, true),
  id: 'tutorial-five-slot-duel-larger', title: '五位逐一比大，赢位多者获胜',
});
export function sampleRules(count, seed = 0) {
  if (!integer(count, 0, 100_000)) throw new TypeError('规则数量须为 0 至 100000 的整数');
  const random = seeded(seed);
  return Array.from({ length: count }, () => generateRule(random));
}

function betErrors(bet) {
  if (!record(bet) || typeof bet.id !== 'string' || !bet.id || typeof bet.name !== 'string' || !bet.name || typeof bet.description !== 'string') return ['赌注元数据无效'];
  const p = bet.predicate;
  if (!record(p) || p.type !== 'compare' || !['gte', 'lte', 'eq'].includes(p.comparison) || !integer(p.target, -MAX_NUMBER, MAX_NUMBER) || Object.keys(p).some(k => !['type', 'expression', 'comparison', 'target'].includes(k))) return ['赌注判断结构无效'];
  if (!record(p.expression) || p.expression.type !== 'metric') return ['赌注须使用有限数字指标'];
  return schemaErrors({ id: 'bet-validation', title: '赌注验证', description: '赌注验证', metric: p.expression.metric, scope: p.expression.scope, mode: 'max', ast: p.expression });
}
/** Serializable predicate evaluation; malformed input fails explicitly. */
export function evaluateBet(bet, board) {
  const errors = betErrors(bet);
  if (errors.length) throw new TypeError(errors.join('；'));
  assertBoard(board);
  return compare(rawValue(bet.predicate.expression, board), bet.predicate.comparison, bet.predicate.target);
}
/** Conservative true/false witnesses, independent of engine and hidden boards. */
export function validateBet(bet) {
  const errors = betErrors(bet);
  if (errors.length) return { valid: false, errors };
  const witnesses = {};
  for (const board of witnessBoards(bet.predicate.expression)) {
    const result = compare(rawValue(bet.predicate.expression, board), bet.predicate.comparison, bet.predicate.target);
    if (!own(witnesses, String(result))) witnesses[String(result)] = structuredClone(board);
    if (own(witnesses, 'true') && own(witnesses, 'false')) return { valid: true, errors: [], witnesses };
  }
  return { valid: false, errors: ['赌注缺少成立或不成立的见证'] };
}
/** Fresh parameters fill typed sentence templates, never serialized functions. */
export function generateBet(random = Math.random) {
  if (typeof random !== 'function') throw new TypeError('random 必须为函数');
  for (let attempt = 0; attempt < 24; attempt++) {
    const metric = pick(random, ['filteredCount', 'filteredCount', 'relationCount', 'sum', 'spread', 'max', 'min', 'thresholdCount', 'targetDistance', 'evenCount']);
    const expressionNode = makeLeaf(random, metric);
    const hasEffects = conditions(expressionNode).flatMap(atoms).some(c => ['attribute', 'keyword', 'status'].includes(c.kind));
    // Numeric targets must be meaningful on ordinary starts, not merely at
    // safety-boundary values. Effect predicates still need installed witnesses.
    const boards = hasEffects ? witnessBoards(expressionNode) : OPENING_WITNESSES;
    const values = [...new Set(boards.map(b => rawValue(expressionNode, b)))].sort((a, b) => a - b);
    if (values.length < 2) continue;
    const comparison = pick(random, ['gte', 'lte', 'eq']);
    // Interior/reachable endpoints ensure a true and a false legal board.
    const candidates = comparison === 'gte' ? values.slice(1) : comparison === 'lte' ? values.slice(0, -1) : values;
    const target = pick(random, candidates);
    const serial = (betSerials.get(random) ?? 0) + 1; betSerials.set(random, serial);
    const bet = {
      id: `bet-${serial.toString(36)}-${Math.floor(draw(random) * 4294967296).toString(36)}`,
      name: `${FAMILY.get(metric).name}${{ gte: '至少', lte: '至多', eq: '恰好' }[comparison]}${target}`,
      description: `${expression(expressionNode)}，结果${{ gte: '大于等于', lte: '小于等于', eq: '等于' }[comparison]} ${target} 时赌注成立，否则不成立。开牌时判断对手盘面。`,
      predicate: { type: 'compare', expression: expressionNode, comparison, target },
    };
    return bet;
  }
  // A pathological RNG can repeatedly choose unsatisfiable effect combinations.
  // The fallback still uses a concrete executable, nonconstant numeric predicate.
  const serial = (betSerials.get(random) ?? 0) + 1; betSerials.set(random, serial);
  return { id: `bet-${serial.toString(36)}-fallback`, name: '中格至少一点', description: '中格数字大于等于 1 时成立，否则不成立。开牌时判断对手盘面。',
    predicate: { type: 'compare', expression: { type: 'metric', metric: 'sum', scope: [4] }, comparison: 'gte', target: 1 } };
}
