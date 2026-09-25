/**
 * 可序列化的确定性随机数（mulberry32）。
 * 同一个种子永远得到同一串结果；状态是一个 32 位整数，可以直接存档。
 */
export class Rng {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** 当前状态，可用于存档与恢复。 */
  snapshot(): number {
    return this.state;
  }

  static restore(state: number): Rng {
    const r = new Rng(0);
    r.state = state >>> 0;
    return r;
  }

  /** [0, 1) 的浮点数。 */
  next(): number {
    let t = (this.state = (this.state + 0x6d2b79f5) >>> 0);
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** [0, n) 的整数。 */
  int(n: number): number {
    if (n <= 0) throw new Error(`Rng.int: n must be positive, got ${n}`);
    return Math.floor(this.next() * n);
  }

  pick<T>(items: readonly T[]): T {
    if (items.length === 0) throw new Error("Rng.pick: empty list");
    return items[this.int(items.length)];
  }

  /** 不放回地取 k 个（保持抽取顺序）。 */
  sample<T>(items: readonly T[], k: number): T[] {
    if (k > items.length) throw new Error(`Rng.sample: k=${k} > ${items.length}`);
    const pool = items.slice();
    const out: T[] = [];
    for (let i = 0; i < k; i++) {
      const j = this.int(pool.length);
      out.push(pool[j]);
      pool.splice(j, 1);
    }
    return out;
  }

  shuffle<T>(items: readonly T[]): T[] {
    return this.sample(items, items.length);
  }
}
