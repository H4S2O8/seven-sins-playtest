import { CHARACTERS } from "../content/characters.js";
import { campaignRoster } from "../content/campaign-cards.js";
import { demonId } from "../content/demons.js";
import type { TableOptions } from "../game/table.js";
import { Rng } from "../rng.js";
import { MIN_CAMPAIGN_POOL, STAGES, STARTING_POOL, stage } from "./stages.js";

/**
 * 战役进度：打到了第几关、你的牌池、每关重来了几次。和自由牌桌分开存档。
 * 这里只有纯数据和纯函数，存到哪里由界面决定。
 */
export interface CampaignProgress {
  /** 已经打过的关数：0 = 还没过序章；STAGES.length = 全部通关。 */
  cleared: number;
  /** 你的牌池。 */
  pool: string[];
  /** 每关输掉之后重来的次数。 */
  retries: number[];
  /** 每关第一次通关时重来了几次（没通关为 null）。 */
  clearedAfter: (number | null)[];
  /** 得到的魔神牌（按关卡顺序）。 */
  demons: string[];
  /** 通关后还没挑的人（刷新页面也不会丢）。 */
  offer: { stage: number; ids: string[] } | null;
}

export function newProgress(): CampaignProgress {
  return {
    cleared: 0,
    pool: STARTING_POOL.slice(),
    retries: STAGES.map(() => 0),
    clearedAfter: STAGES.map(() => null),
    demons: [],
    offer: null,
  };
}

/** 读存档时用：字段缺了、编号不认识就返回 null，由调用方重开。 */
export function checkProgress(v: unknown): CampaignProgress | null {
  const p = v as CampaignProgress | null;
  if (!p || typeof p.cleared !== "number" || !Array.isArray(p.pool) || !Array.isArray(p.retries)) return null;
  if (p.cleared < 0 || p.cleared > STAGES.length) return null;
  const known = new Set(CHARACTERS.map((c) => c.id));
  if (p.pool.length < MIN_CAMPAIGN_POOL || p.pool.some((id) => !known.has(id))) return null;
  return {
    cleared: p.cleared,
    pool: p.pool.slice(),
    retries: STAGES.map((_, i) => Number(p.retries[i]) || 0),
    clearedAfter: STAGES.map((_, i) => (Array.isArray(p.clearedAfter) && typeof p.clearedAfter[i] === "number" ? p.clearedAfter[i] : null)),
    demons: Array.isArray(p.demons) ? p.demons.filter((d) => typeof d === "string") : [],
    offer: p.offer && Array.isArray(p.offer.ids) && p.offer.ids.every((id) => known.has(id)) ? { stage: p.offer.stage, ids: p.offer.ids.slice() } : null,
  };
}

/** 能打的关：打过的都能重打，再加下一关。 */
export function unlocked(p: CampaignProgress, no: number): boolean {
  return no >= 0 && no < STAGES.length && no <= p.cleared;
}

/**
 * 这一关的牌桌设置。seat 0 是你，seat 1 是她。
 * demon：你这张牌桌带的魔神牌（名字，从已经拿到的里挑；null = 不带）。
 */
export function stageTable(p: CampaignProgress, no: number, seed: number, demon: string | null = null): TableOptions {
  const s = stage(no);
  if (demon !== null && !p.demons.includes(demon)) throw new Error(`还没拿到魔神牌：${demon}`);
  return {
    seed,
    buyIn: s.buyIn,
    baseAnte: s.baseAnte,
    blindEvery: s.blindEvery,
    campaign: {
      rules: s.rules.slice(),
      arenaId: s.arenaId,
      arenaActive: s.arenaActive,
      pools: [p.pool.slice(), s.foePool.slice()],
      deal: s.deal,
      betting: s.betting,
      battle: {
        hellfire: true,
        cards: true,
        nearest: true,
        demons: [demon && demonId(demon), s.demon && demonId(s.demon)],
      },
    },
  };
}

/** 输了：记一次重来，返回她这次的嘲讽。 */
export function recordLoss(p: CampaignProgress, no: number, rng: Rng): string {
  p.retries[no]++;
  return taunt(no, p.retries[no], rng);
}

/** 重来次数分档：第 1 次、第 2–3 次、第 4–6 次、第 7 次起。 */
export function tauntTier(retries: number): 0 | 1 | 2 | 3 {
  if (retries <= 1) return 0;
  if (retries <= 3) return 1;
  if (retries <= 6) return 2;
  return 3;
}

export function taunt(no: number, retries: number, rng: Rng): string {
  return rng.pick(stage(no).taunts[tauntTier(retries)]);
}

/**
 * 赢了：第一次通关才推进进度、拿魔神牌、挑人。
 * 返回挑人的候选（序章和重打时没有，为空），同时记在 p.offer 里等玩家挑。
 */
export function recordWin(p: CampaignProgress, no: number, seed: number): string[] {
  if (no !== p.cleared) return [];
  const s = stage(no);
  p.cleared = no + 1;
  p.clearedAfter[no] = p.retries[no];
  if (s.demon) p.demons.push(s.demon);
  const ids = no === 0 ? [] : rewardOffer(p, no, seed);
  p.offer = ids.length ? { stage: no, ids } : null;
  return ids;
}

/**
 * 3 名候选：优先她那一罪的招牌人物，不够的从同罪、再从全体里补；已经在牌池里的不出。
 * 只从下一关起能用的人物里挑（战役移出的、机制还没教到的不出）。
 */
export function rewardOffer(p: CampaignProgress, no: number, seed: number): string[] {
  const s = stage(no);
  const rng = new Rng(seed);
  const have = new Set(p.pool);
  const roster = new Set(campaignRoster(Math.min(no + 1, STAGES.length - 1)));
  const fresh = (ids: readonly string[]) => ids.filter((id) => roster.has(id) && !have.has(id));
  const out: string[] = [];
  const take = (ids: string[]) => {
    for (const id of rng.shuffle(ids)) if (out.length < 3 && !out.includes(id)) out.push(id);
  };
  take(fresh(s.signature));
  take(fresh(CHARACTERS.filter((c) => c.sin === s.sin).map((c) => c.id)));
  take(fresh(CHARACTERS.map((c) => c.id)));
  return out;
}

/** 挑一名进牌池，然后可以移除一名（remove 为 null 不移除；牌池不能少于下限）。 */
export function applyReward(p: CampaignProgress, pick: string, remove: string | null): void {
  if (p.pool.includes(pick)) throw new Error("这名人物已经在牌池里了");
  let i = -1;
  if (remove !== null) {
    i = p.pool.indexOf(remove);
    if (i < 0) throw new Error("牌池里没有这名人物");
    if (p.pool.length < MIN_CAMPAIGN_POOL) throw new Error(`牌池至少保留 ${MIN_CAMPAIGN_POOL} 名`);
  }
  if (i >= 0) p.pool.splice(i, 1);
  p.pool.push(pick);
  p.offer = null;
}
