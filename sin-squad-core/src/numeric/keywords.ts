/** Bounded reactions. Generated reactions never recursively trigger reactions. */
export type Keyword =
  | "ward"
  | "guard"
  | "intercept"
  | "legacy"
  | "echo"
  | "reserve"
  | "rage"
  | "pursuit"
  | "inspire"
  | "command"
  | "link";
export interface KeywordSpec {
  kind: Keyword;
  value: number;
}
export const KEYWORDS: Record<
  Keyword,
  { name: string; icon: string; description: string }
> = {
  ward: {
    name: "护盾",
    icon: "◈",
    description:
      "挡住一次敌方人物或装备施加的沉默、封印或减力。场地及己方效果不受阻挡。",
  },
  guard: {
    name: "护送",
    icon: "♜",
    description:
      "替相邻队友承受第一次敌方沉默或封印；先检查队友自己的护盾，再护送。多名护送者优先左侧，护送不再次转移。",
  },
  intercept: {
    name: "截流",
    icon: "⇄",
    description:
      "夺取对位第一次人物或装备增益中的指定点数，每手一次；不夺取场地、遗赠、共鸣或蓄能释放。",
  },
  legacy: {
    name: "遗赠",
    icon: "✧",
    description:
      "被沉默仍触发：控制阶段结束后，将指定力量赠给原始数字最低的其他队友；同值选左侧。",
  },
  echo: {
    name: "共鸣",
    icon: "⌁",
    description:
      "第一次收到其他队友的人物或装备正向增益时，另赠指定力量给原始数字最低的其他队友。每手一次，不递归触发共鸣；支援被蓄能暂存或截流仍算收到。",
  },
  reserve: {
    name: "蓄能",
    icon: "⚡",
    description:
      "暂存收到的人物、装备和衍生增益，最多指定点数；先于截流暂存。末段返还暂存量，另加其一半（向下取整）。自己、队友、遗赠、共鸣均可供能；释放不再触发反应。",
  },
  rage: {
    name: "激怒",
    icon: "✹",
    description:
      "受到人物或装备的实际减力（含己方牺牲），或增益被截流后，追猎之前增加指定力量，每手一次；追猎造成的减力不会再激怒。护盾挡下不算；人物激怒被沉默便失效。",
  },
  pursuit: {
    name: "追猎",
    icon: "➶",
    description:
      "蓄能释放后，若本位领先，令敌方其他位置中原始数字最低者失去指定力量。双方按同一快照判定，仅一轮，不追猎连锁。",
  },
  inspire: {
    name: "激励",
    icon: "♧",
    description:
      "控制结束后，其他队友的每一种不同生效关键词令自己 +1，最多指定点数；同名不重复计数。",
  },
  command: {
    name: "统御",
    icon: "♛",
    description:
      "控制结束后，若其他队友有人拥有生效的护盾或护送，自己获得指定力量。护盾即使已消耗，也算拥有。",
  },
  link: {
    name: "结盟",
    icon: "⋈",
    description:
      "控制结束后，自己拥有至少两种不同生效关键词时，左右邻位各获得指定力量。人物和装备共同计数。",
  },
};
export const keywordText = (xs: readonly KeywordSpec[]) =>
  xs
    .map(
      (x) =>
        `${KEYWORDS[x.kind].name}${["ward", "guard"].includes(x.kind) ? "" : ` ${x.value}`}：${KEYWORDS[x.kind].description}`,
    )
    .join(" ");
type Card = { id: string; keywords?: readonly KeywordSpec[] };
type Hit = {
  sourceId: string;
  seat: 0 | 1;
  pos: number;
  targetSeat: 0 | 1;
  targetPos: number;
  amount: number;
  text: string;
  stage: string;
};
type Entry = {
  kind: Keyword;
  value: number;
  sourceId: string;
  seat: 0 | 1;
  pos: number;
};
export class KeywordCombat {
  private used = new Set<string>();
  private stored = [
    [0, 0, 0],
    [0, 0, 0],
  ];
  private hurt = [
    [false, false, false],
    [false, false, false],
  ];
  private queue: Hit[] = [];
  private controlEntries: Entry[][][] = [];
  constructor(
    private cards: Card[][],
    private equipment: (Card | null)[][],
    private raw: number[][],
    private powers: number[][],
    private silenced: boolean[][],
    private sealed: boolean[][],
    private record: (h: Hit, before: number, after: number) => void,
  ) {}
  private entries(s: number, p: number, innate = false): Entry[] {
    const all = [
      ...(!this.silenced[s][p] || innate
        ? (this.cards[s][p].keywords ?? [])
        : []
      ).map((k) => ({ ...k, sourceId: this.cards[s][p].id })),
      ...(!this.sealed[s][p] ? (this.equipment[s][p]?.keywords ?? []) : []).map(
        (k) => ({ ...k, sourceId: this.equipment[s][p]!.id }),
      ),
    ];
    // Identical keywords on a character and equipment use the stronger value.
    return all
      .filter(
        (x, i) =>
          !all.some(
            (y, j) =>
              y.kind === x.kind &&
              (y.value > x.value || (y.value === x.value && j < i)),
          ),
      )
      .map((x) => ({ ...x, seat: s as 0 | 1, pos: p }));
  }
  private key(e: Entry) {
    return `${e.seat}:${e.pos}:${e.kind}`;
  }
  private take(e: Entry | undefined) {
    if (!e || this.used.has(this.key(e))) return false;
    this.used.add(this.key(e));
    return true;
  }
  private find(s: number, p: number, k: Keyword) {
    return this.entries(s, p).find((x) => x.kind === k);
  }
  private note(e: Entry, text: string) {
    this.record(
      {
        ...e,
        targetSeat: e.seat,
        targetPos: e.pos,
        amount: 0,
        text,
        stage: "keyword",
      },
      this.powers[e.seat][e.pos],
      this.powers[e.seat][e.pos],
    );
  }
  private gift(
    e: Entry,
    targetSeat: 0 | 1,
    targetPos: number,
    amount: number,
    text: string,
  ): Hit {
    return {
      sourceId: e.sourceId,
      seat: e.seat,
      pos: e.pos,
      targetSeat,
      targetPos,
      amount,
      text,
      stage: "keyword",
    };
  }
  private weakest(s: number, except: number) {
    return [0, 1, 2]
      .filter((p) => p !== except)
      .sort((a, b) => this.raw[s][a] - this.raw[s][b] || a - b)[0];
  }
  lockControl() {
    this.controlEntries = [0, 1].map((s) =>
      [0, 1, 2].map((p) => this.entries(s, p)),
    );
  }
  control(
    s: 0 | 1,
    p: number,
    targetSeat: 0 | 1,
    targetPos: number,
  ): number | null {
    if (s === targetSeat) return targetPos;
    const ward = this.controlEntries[targetSeat][targetPos].find(
      (e) => e.kind === "ward",
    );
    if (this.take(ward)) {
      this.note(ward!, "护盾挡下敌方控制");
      return null;
    }
    const guard = this.controlEntries[targetSeat]
      .flat()
      .find(
        (e) =>
          e.kind === "guard" &&
          Math.abs(e.pos - targetPos) === 1 &&
          !this.used.has(this.key(e)),
      );
    if (this.take(guard)) {
      this.note(guard!, "护送：替相邻队友承受控制");
      targetPos = guard!.pos;
      const ownWard = this.controlEntries[targetSeat][targetPos].find(
        (e) => e.kind === "ward",
      );
      if (this.take(ownWard)) {
        this.note(ownWard!, "护盾挡下护送来的控制");
        return null;
      }
    }
    return targetPos;
  }
  power(h: Hit, react = true, store = react) {
    let amount = h.amount;
    const s = h.targetSeat,
      p = h.targetPos;
    if (amount < 0 && h.seat !== s) {
      const ward = this.find(s, p, "ward");
      if (this.take(ward)) {
        this.note(ward!, "护盾挡下敌方减力");
        return;
      }
    }
    if (amount < 0) this.hurt[s][p] = true;
    // A support packet is received even when its power is stored or intercepted.
    if (react && amount > 0 && h.seat === s && h.pos !== p) {
      const echo = this.find(s, p, "echo");
      if (this.take(echo))
        this.queue.push(
          this.gift(
            echo!,
            s,
            this.weakest(s, p),
            echo!.value,
            "共鸣：将支援传给弱位",
          ),
        );
    }
    if (store && amount > 0) {
      const reserve = this.find(s, p, "reserve");
      if (reserve) {
        const n = Math.min(
          amount,
          Math.max(0, reserve.value - this.stored[s][p]),
        );
        this.stored[s][p] += n;
        amount -= n;
        if (n) this.note(reserve, `蓄能暂存 ${n} 点`);
      }
    }
    if (react && amount > 0) {
      const intercept = this.find(1 - s, p, "intercept");
      if (amount > 0 && this.take(intercept)) {
        const n = Math.min(amount, intercept!.value);
        amount -= n;
        if (n) this.hurt[s][p] = true;
        this.queue.push(
          this.gift(intercept!, intercept!.seat, p, n, `截流夺取 ${n} 点`),
        );
      }
    }
    const before = this.powers[s][p];
    this.powers[s][p] += amount;
    if (h.amount)
      this.record(
        {
          ...h,
          amount,
          text: h.text + (amount === 0 ? "（增益已暂存或截流）" : ""),
        },
        before,
        this.powers[s][p],
      );
  }
  flush() {
    for (const h of this.queue) this.power(h, false, true);
    this.queue = [];
  }
  legacies() {
    for (const s of [0, 1] as const)
      for (let p = 0; p < 3; p++)
        if (this.silenced[s][p]) {
          const e = this.entries(s, p, true).find((x) => x.kind === "legacy");
          if (e)
            this.power(
              this.gift(
                e,
                s,
                this.weakest(s, p),
                e.value,
                "遗赠：沉默后留下力量",
              ),
              false,
              true,
            );
        }
  }
  formations() {
    const pending: Hit[] = [];
    for (const s of [0, 1] as const)
      for (let p = 0; p < 3; p++) {
        const own = this.entries(s, p),
          others = [0, 1, 2]
            .filter((j) => j !== p)
            .flatMap((j) => this.entries(s, j));
        const inspire = own.find((e) => e.kind === "inspire");
        if (inspire) {
          const n = Math.min(
            inspire.value,
            new Set(others.map((e) => e.kind)).size,
          );
          if (n)
            pending.push(
              this.gift(inspire, s, p, n, "激励：队友的不同关键词增强自己"),
            );
        }
        const command = own.find((e) => e.kind === "command");
        if (
          command &&
          others.some((e) => e.kind === "ward" || e.kind === "guard")
        )
          pending.push(
            this.gift(
              command,
              s,
              p,
              command.value,
              "统御：护盾或护送队友提供力量",
            ),
          );
        const link = own.find((e) => e.kind === "link");
        if (link && own.length >= 2)
          for (const q of [p - 1, p + 1])
            if (q >= 0 && q < 3)
              pending.push(
                this.gift(link, s, q, link.value, "结盟：双关键词支援邻位"),
              );
      }
    for (const h of pending) this.power(h);
    this.flush();
  }
  finish() {
    this.flush();
    for (const s of [0, 1] as const)
      for (let p = 0; p < 3; p++) {
        const rage = this.find(s, p, "rage");
        if (rage && this.hurt[s][p])
          this.power(
            this.gift(
              rage,
              s,
              p,
              rage.value,
              "激怒：力量受损或增益被截流后反击",
            ),
            false,
            true,
          );
        const reserve = this.find(s, p, "reserve"),
          n = this.stored[s][p];
        if (reserve && n)
          this.power(
            this.gift(
              reserve,
              s,
              p,
              n + Math.floor(n / 2),
              `蓄能释放 ${n}，充能奖励 ${Math.floor(n / 2)}`,
            ),
            false,
          );
      }
    const chase: Hit[] = [];
    for (const s of [0, 1] as const)
      for (let p = 0; p < 3; p++) {
        const e = this.find(s, p, "pursuit");
        if (e && this.powers[s][p] > this.powers[1 - s][p])
          chase.push(
            this.gift(
              e,
              (1 - s) as 0 | 1,
              this.weakest(1 - s, p),
              -e.value,
              "追猎：领先位压制另一弱位",
            ),
          );
      }
    for (const h of chase) this.power(h, false);
  }
}
