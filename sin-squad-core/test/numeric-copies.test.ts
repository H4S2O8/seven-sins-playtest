import { it, expect } from "vitest";
import { NumericTable } from "../src/numeric/table.js";
it("deals independent copies, keeps three identical cards and restores each occurrence", () => {
  let t: NumericTable | undefined,
    id = "";
  for (let seed = 1; seed < 1000; seed++) {
    const candidate = new NumericTable({ seed });
    const ids = candidate.observe(0).me.current;
    id = ids.find((x) => ids.filter((y) => y === x).length >= 3) ?? "";
    if (id) {
      t = candidate;
      break;
    }
  }
  expect(t).toBeTruthy();
  for (let n = 0; n < 3; n++)
    t!.apply(0, { type: "keep", index: t!.observe(0).me.current.indexOf(id) });
  expect(t!.observe(0).me.kept).toEqual([id, id, id]);
  while (t!.phase === "draft") t!.apply(1, t!.aiAction(1, "aggressive")!);
  t!.apply(0, { type: "place", numbers: [2, 0, 1], effects: [1, 2, 0] });
  const copy = NumericTable.restore(t!.save());
  expect(copy.observe(0)).toEqual(t!.observe(0));
  expect(copy.observe(0).me.slots?.map((x) => x.effectId)).toEqual([
    id,
    id,
    id,
  ]);
});
it("AI occurrence counts never select a missing duplicate", () => {
  for (let seed = 1; seed <= 8; seed++) {
    const t = new NumericTable({ seed });
    let n = 0;
    while (t.phase === "draft" && n++ < 20) {
      const s = t.observe(0).toAct[0] as 0 | 1;
      const a = t.aiAction(s)!;
      if (a.type === "keep") expect(a.index).toBeGreaterThanOrEqual(0);
      t.apply(s, a);
    }
    expect(t.phase).toBe("place");
  }
});
