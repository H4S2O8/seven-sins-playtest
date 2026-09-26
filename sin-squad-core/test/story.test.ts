import { describe, expect, it } from "vitest";
import { STAGES } from "../src/campaign/stages.js";
import { SCENES, hostOf, linesFor, scene, speakerStage } from "../src/campaign/story.js";

describe("战役剧情", () => {
  it("每一层都有关前、关后两段，主人对得上", () => {
    for (const s of STAGES) {
      expect(scene(s.no, "before").lines.length).toBeGreaterThan(2);
      expect(scene(s.no, "after").lines.length).toBeGreaterThan(2);
      expect(speakerStage(hostOf(s.no)).foe).toBe(s.foe);
    }
    expect(new Set(SCENES.map((x) => x.id)).size).toBe(SCENES.length);
  });

  it("台词不出现游戏外的词", () => {
    const banned = ["序章", "关卡", "教学", "存档", "读档", "关前", "关后", "玩家", "游戏"];
    for (const sc of SCENES) for (const l of sc.lines) for (const w of banned) expect(l.text, `${sc.id}：${l.text}`).not.toContain(w);
  });

  it("一段剧情里最多两个人说话（左右各一个站位）", () => {
    for (const sc of SCENES) expect(new Set(sc.lines.map((l) => l.who).filter(Boolean)).size, sc.id).toBeLessThanOrEqual(2);
  });

  it("没重来过就不提次数；重来过把 {N} 换成次数", () => {
    const sc = scene(3, "after");
    expect(linesFor(sc, 0).some((l) => l.retried)).toBe(false);
    const again = linesFor(sc, 4);
    expect(again[0].text).toContain("第 4 次");
    expect(again.some((l) => l.text.includes("{N}"))).toBe(false);
    for (const x of SCENES) for (const l of x.lines) if (l.text.includes("{N}")) expect(l.retried, l.text).toBe(true);
  });

  it("关后每一层都有阿斯莫德（她自己那一层是主人）", () => {
    for (const s of STAGES) expect(scene(s.no, "after").lines.some((l) => l.who === "asmodeus"), s.foe).toBe(true);
  });
});
