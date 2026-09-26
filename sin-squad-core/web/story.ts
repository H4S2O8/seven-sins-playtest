import { stage } from "../src/campaign/stages.js";
import { hostOf, speakerStage, type Line, type Scene, type Speaker } from "../src/campaign/story.js";
import { stageColor, stageFace } from "./campaign.js";
import { SIN_LATIN } from "./sigil.js";
import { esc } from "./text.js";

/**
 * 剧情播放：一句一句的视觉小说。画在入场那一层 #gate 里，点击统一走 data-go，由 intro.ts 的 Gate 处理。
 *
 * - 背景是这一层的主场插画；这一层的主人站在左边，来串门的（阿斯莫德、看板娘）第一次开口时从右边进场；
 * - 说话的人亮着，另一位压暗；旁白两边都压暗，字是斜的、没有名牌；
 * - 字一个一个打出来，打字途中点一下先把这句显示完，再点才到下一句；
 * - 表情差分还没画，先用立绘的小动作代替（生气抖一下、动摇晃一下、败北褪色、得意抬一下）。
 */

const CHAR_MS = 32;

/** 这段剧情里除了这一层主人之外、第一个开口的人（站右边）。 */
function guestOf(sc: Scene, lines: Line[]): Speaker | null {
  const host = hostOf(sc.stage);
  return lines.find((l) => l.who && l.who !== host)?.who ?? null;
}

/** 某一句时，两个站位的样子：主人一直在场；客人第一次开口才进场；说话的亮、另一位压暗。 */
function slotClass(sc: Scene, lines: Line[], i: number, side: "host" | "guest"): { who: Speaker | null; cls: string; mood: string | null } {
  const who = side === "host" ? hostOf(sc.stage) : guestOf(sc, lines);
  const line = lines[i];
  const on = side === "host" || lines.slice(0, i + 1).some((l) => l.who === who);
  const speaking = !!who && line.who === who;
  return { who, cls: [on && "on", speaking && "speaking", on && !speaking && "quiet"].filter(Boolean).join(" "), mood: speaking ? line.mood ?? null : null };
}

function face(sc: Scene, lines: Line[], i: number, art: Set<string>, side: "host" | "guest"): string {
  const st = slotClass(sc, lines, i, side);
  if (!st.who) return "";
  return `<div class="story-slot ${side} ${st.cls}"${st.mood ? ` data-mood="${st.mood}"` : ""}>${stageFace(speakerStage(st.who), art, "vn-face story-face")}</div>`;
}

/** 一句台词：名牌 + 一个字一个字打出来的正文。 */
function lineHtml(line: Line, i: number, total: number): string {
  const who = line.who ? speakerStage(line.who) : null;
  const chars = Array.from(line.text).map((c, k) => `<span style="--k:${k}">${esc(c)}</span>`).join("");
  const plate = who
    ? `<div class="vn-name" style="--sin:${stageColor(who)}"><b>${who.foe}</b><small>${who.sin ? SIN_LATIN[who.sin] : "TABERNA"}</small></div>`
    : "";
  return `${plate}<p class="vn-line story-line ${who ? "" : "narration"}" style="--ms:${CHAR_MS}ms">${chars}</p>
    <div class="story-foot"><small>${i + 1} / ${total}</small><span class="story-next" aria-hidden="true">▼</span></div>`;
}

/** 整一幕：背景、两个站位、对话框、跳过按钮。 */
export function storyView(art: Set<string>, sc: Scene, lines: Line[], i: number): string {
  const s = stage(sc.stage);
  const bg = art.has(s.arenaId) ? `;--scene:url('art/${s.arenaId}.webp')` : "";
  return `<div class="vn story" style="--sin:${stageColor(s)}${bg}" data-go="storyNext">
    <div class="vn-bg"></div><div class="embers">${"<i></i>".repeat(14)}</div>
    <button class="story-skip" data-go="storySkip">跳过 ›</button>
    <div class="story-cast">${face(sc, lines, i, art, "host")}${face(sc, lines, i, art, "guest")}</div>
    <div class="vn-dialog story-dialog" role="button" tabindex="0" aria-live="polite" autofocus>${lineHtml(lines[i], i, lines.length)}</div>
  </div>`;
}

/**
 * 换到第 i 句：只改对话框和站位的状态，不重画整幕（重画会让背景和立绘的入场动画从头再播）。
 * 返回这一句打完字的时间（毫秒）。
 */
export function storyPatch(root: HTMLElement, sc: Scene, lines: Line[], i: number): number {
  for (const side of ["host", "guest"] as const) {
    const el = root.querySelector<HTMLElement>(`.story-slot.${side}`);
    if (!el) continue;
    const st = slotClass(sc, lines, i, side);
    el.className = `story-slot ${side} ${st.cls}`;
    // 表情：换一句就重播一次小动作
    el.removeAttribute("data-mood");
    if (st.mood) { void el.offsetWidth; el.dataset.mood = st.mood; }
  }
  const box = root.querySelector<HTMLElement>(".story-dialog");
  if (box) box.innerHTML = lineHtml(lines[i], i, lines.length);
  return Array.from(lines[i].text).length * CHAR_MS;
}

/** 打字途中点一下：这句直接显示完。 */
export function storyFinishLine(root: HTMLElement) {
  root.querySelector(".story-line")?.classList.add("shown");
}
