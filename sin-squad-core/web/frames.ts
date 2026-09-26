import { CHARACTERS, character } from "../src/content/characters.js";
import type { AttackShape } from "../src/types.js";
import { esc } from "./text.js";

/**
 * 人物牌的卡框样式。卡面的 HTML 只有一套（main.ts 的 cardFront），换卡框只换 CSS：
 * 根元素上的 data-frame 决定用哪套（style.css 里 [data-frame="…"] .person 开头的规则），classic 是原来那套。
 * 有的卡框要用到 SVG 画的框线、窗形、纹样，这里生成后挂在根元素的 CSS 变量（--fr-…）上。
 */

export type FrameId = "classic" | "vitrail" | "codex" | "reliquary" | "arcana";

export const FRAMES: ReadonlyArray<{ id: FrameId; name: string; latin: string; about: string }> = [
  { id: "vitrail", name: "花窗", latin: "VITRAIL", about: "哥特教堂的尖拱窗：人物站在罪色的菱格彩玻璃前，石雕窗框、铅条金线，数值是两扇小玫瑰窗。和牌背的玫瑰窗是一家。" },
  { id: "codex", name: "圣典", latin: "CODEX", about: "中世纪泥金手抄本：羊皮纸卡面、描金边框、罪色的菱格底纹衬着人物，名字用朱红书写，数值盖成两枚火漆印。" },
  { id: "reliquary", name: "圣物匣", latin: "RELIQUARY", about: "鎏金的圣物匣：厚重的金框和四角卷草，顶上嵌一颗罪色宝石，人物在圆拱玻璃窗后，名字刻在金绶带上；攻是金盾，血是一滴红宝石。" },
  { id: "arcana", name: "塔罗", latin: "ARCANA", about: "塔罗大阿卡纳：立绘铺满整张牌，罪色的光芒从头后放射，新艺术风格的细金线勾出拱形画框，数值像扑克牌角标一样写在两角。" },
  { id: "classic", name: "经典", latin: "CLASSICUS", about: "现在用的卡框：深色牌面、金线、圆形数值徽记。" },
];

const KEY = "sinsquad.frame";
const isFrame = (s: string | null): s is FrameId => !!s && FRAMES.some((f) => f.id === s);

/** 网址里的 ?frame= 优先（并记住），其次是上次选的，默认还是原来那套。 */
export function currentFrame(): FrameId {
  const q = new URLSearchParams(location.search).get("frame");
  if (isFrame(q)) { saveFrame(q); return q; }
  try {
    const v = localStorage.getItem(KEY);
    if (isFrame(v)) return v;
  } catch { /* 无所谓 */ }
  return "classic";
}

function saveFrame(id: FrameId) {
  try { localStorage.setItem(KEY, id); } catch { /* 无所谓 */ }
}

export function applyFrame(id: FrameId) {
  document.documentElement.dataset.frame = id;
}

// ───────────────────────── 卡框用到的 SVG ─────────────────────────

const f = (n: number) => +n.toFixed(2);
const url = (svg: string) => `url("data:image/svg+xml,${encodeURIComponent(svg)}")`;
const svg = (vb: string, body: string, defs = "") =>
  `<svg xmlns='http://www.w3.org/2000/svg' viewBox='${vb}' preserveAspectRatio='none'>${defs ? `<defs>${defs}</defs>` : ""}${body}</svg>`;
const GOLD = `<linearGradient id='g' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#f6e2a8'/><stop offset='.5' stop-color='#d4ac5a'/><stop offset='1' stop-color='#8a6424'/></linearGradient>`;
/** 斜着打光的金：用在大面积的金框上，比上下渐变更像金属。 */
const GOLD_SHEEN = `<linearGradient id='s' x1='0' y1='0' x2='1' y2='1'><stop offset='0' stop-color='#fff1c4'/><stop offset='.18' stop-color='#d9b25f'/><stop offset='.36' stop-color='#8a6424'/><stop offset='.52' stop-color='#f0d48e'/><stop offset='.7' stop-color='#a57a32'/><stop offset='.86' stop-color='#e8c878'/><stop offset='1' stop-color='#6e4a14'/></linearGradient>`;

/** 细颗粒噪点（黑色、半透明），石头和羊皮纸的质感。 */
function grain(alpha: number, freq: number) {
  return `<svg xmlns='http://www.w3.org/2000/svg' width='160' height='160'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='${freq}' numOctaves='3' stitchTiles='stitch'/>` +
    `<feColorMatrix values='0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  ${alpha} 0 0 0 ${f(-alpha * 0.35)}'/></filter><rect width='160' height='160' filter='url(#n)'/></svg>`;
}

/**
 * 压低的尖拱：两段大半径圆弧在正中相交，和两侧竖边在起拱处成一个折角（比等边尖拱矮，立绘窗放得下）。
 * x0..x1 是两侧的墙，top 是拱尖，rise 是拱高，r 是圆弧半径。
 */
function pointedArch(x0: number, x1: number, top: number, bottom: number, r: number, rise: number, close = true) {
  const mid = (x0 + x1) / 2;
  const spring = top + rise;
  return `M${f(x0)} ${f(bottom)}V${f(spring)}A${r} ${r} 0 0 1 ${f(mid)} ${f(top)}A${r} ${r} 0 0 1 ${f(x1)} ${f(spring)}V${f(bottom)}${close ? "Z" : ""}`;
}

/** 花窗：立绘窗是 88 × 62（牌宽 × 0.88、0.62），尖拱遮罩、拱框、窗外两角的三叶饰，以及拱内的菱格彩玻璃。 */
function vitrail() {
  const W = 88;
  const H = 62;
  const outer = (close: boolean) => pointedArch(1.6, W - 1.6, 1.6, H, 66, 25, close);
  const inner = pointedArch(4.8, W - 4.8, 5.4, H, 60, 22.5, false);
  const mask = svg(`0 0 ${W} ${H}`, `<path d='${outer(true)}' fill='#000'/>`);
  const trefoil = (cx: number, cy: number) => {
    const lobes = [0, 120, 240].map((d) => {
      const a = ((d - 90) * Math.PI) / 180;
      return `<circle cx='${f(cx + 1.9 * Math.cos(a))}' cy='${f(cy + 1.9 * Math.sin(a))}' r='1.5'/>`;
    }).join("");
    return `<circle cx='${cx}' cy='${cy}' r='4.6' stroke-width='.8'/><g stroke-width='.5'>${lobes}</g>`;
  };
  // 拱框：外面一道铅条（黑）、里面一道金线，再往里一道细金线
  const frame = svg(`0 0 ${W} ${H}`,
    `<path d='${outer(false)}' fill='none' stroke='#0b0907' stroke-width='3.6'/>` +
    `<path d='${outer(false)}' fill='none' stroke='url(#g)' stroke-width='1.5'/>` +
    `<path d='${inner}' fill='none' stroke='#e9cf8f' stroke-opacity='.5' stroke-width='.45'/>` +
    // 右上角那一朵被“查看”按钮占着（按钮做成同样的小圆饰），只画左边
    `<g fill='none' stroke='url(#g)'>${trefoil(8, 8.4)}</g>`,
    GOLD);
  // 彩玻璃：斜菱格（quarry glass），每块玻璃深浅不一，铅条是深色细线；底色由 CSS 的罪色给
  let panes = "";
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const w = 11;
  const h = 15;
  for (let row = -1; row < H / (h / 2) + 1; row++) {
    for (let col = -1; col < W / w + 1; col++) {
      const cx = col * w + (row % 2 ? w / 2 : 0);
      const cy = row * (h / 2);
      const v = rnd();
      const fill = v < 0.5 ? `#fff' fill-opacity='${f(0.04 + v * 0.22)}` : `#000' fill-opacity='${f((v - 0.5) * 0.5)}`;
      panes += `<path d='M${f(cx)} ${f(cy - h / 2)}L${f(cx + w / 2)} ${f(cy)}L${f(cx)} ${f(cy + h / 2)}L${f(cx - w / 2)} ${f(cy)}Z' fill='${fill}'/>`;
    }
  }
  const glass = svg(`0 0 ${W} ${H}`,
    `<g stroke='#0b0907' stroke-opacity='.75' stroke-width='.7' stroke-linejoin='round'>${panes}</g>` +
    // 拱内一圈边带：窄条玻璃
    `<path d='${inner}' fill='none' stroke='#0b0907' stroke-opacity='.8' stroke-width='3.2'/>` +
    `<path d='${inner}' fill='none' stroke='#fff' stroke-opacity='.16' stroke-width='2'/>`);
  return { mask, frame, glass };
}

/** 圣典：整张牌 100 × 142 的描金框（金带、四角方钉、叶饰），罪色的内框带（遮罩，颜色由 CSS 给），立绘后面的菱格底纹。 */
function codex() {
  const leaf = (x: number, y: number, sx: number, sy: number) =>
    `<g transform='translate(${x} ${y}) scale(${sx} ${sy})'>` +
    `<path d='M0 0C3 1.2 6.5 4 7.6 8.8' fill='none' stroke='url(#g)' stroke-width='.55'/>` +
    `<path d='M4.8 3.2C6.8 1.4 9.4 1.6 10.4 2.6C8.8 4.6 6.6 4.8 4.8 3.2Z' fill='url(#g)'/>` +
    `<path d='M6.6 6.2C6.2 8.8 7.6 10.8 9 11.2C9.6 9 8.6 7 6.6 6.2Z' fill='url(#g)'/>` +
    `<circle cx='2.6' cy='4.4' r='.7' fill='url(#g)'/></g>`;
  const boss = (x: number, y: number) =>
    `<rect x='${x - 3.2}' y='${y - 3.2}' width='6.4' height='6.4' fill='url(#s)' stroke='#2a1a0c' stroke-width='.45'/>` +
    `<rect x='${x - 1.6}' y='${y - 1.6}' width='3.2' height='3.2' transform='rotate(45 ${x} ${y})' fill='#7a1c12' stroke='#f6e2a8' stroke-width='.3'/>`;
  const frame = svg("0 0 100 142",
    `<path d='M0 0H100V142H0Z M3.4 3.4V138.6H96.6V3.4Z' fill='url(#s)' fill-rule='evenodd'/>` +
    `<rect x='.5' y='.5' width='99' height='141' fill='none' stroke='#2a1a0c' stroke-width='.8'/>` +
    `<rect x='3.4' y='3.4' width='93.2' height='135.2' fill='none' stroke='#2a1a0c' stroke-width='.6'/>` +
    `<rect x='6.2' y='6.2' width='87.6' height='129.6' fill='none' stroke='#2a1a0c' stroke-width='.4'/>` +
    boss(3.4, 3.4) + boss(96.6, 3.4) + boss(3.4, 138.6) + boss(96.6, 138.6) +
    leaf(7.6, 7.6, 1, 1) + leaf(92.4, 7.6, -1, 1) + leaf(7.6, 134.4, 1, -1) + leaf(92.4, 134.4, -1, -1),
    GOLD + GOLD_SHEEN);
  // 罪色内框带：金带里面一条 1.6 宽的色带
  const band = svg("0 0 100 142", `<path d='M4.1 4.1H95.9V137.9H4.1Z M5.7 5.7V136.3H94.3V5.7Z' fill='#000' fill-rule='evenodd'/>`);
  // 菱格底纹：金色细格线、交点金点、格心一朵小四瓣花；透明的格子里透出罪色
  const diaper = `<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 20 20'><defs>${GOLD}</defs>` +
    `<path d='M0 10L10 0L20 10L10 20Z' fill='#000' fill-opacity='.18'/>` +
    `<path d='M0 10L10 0L20 10L10 20Z' fill='none' stroke='url(#g)' stroke-width='.7'/>` +
    `<g fill='url(#g)'><circle cx='10' cy='0' r='1.3'/><circle cx='10' cy='20' r='1.3'/><circle cx='0' cy='10' r='1.3'/><circle cx='20' cy='10' r='1.3'/>` +
    `<circle cx='10' cy='8.3' r='1'/><circle cx='10' cy='11.7' r='1'/><circle cx='8.3' cy='10' r='1'/><circle cx='11.7' cy='10' r='1'/></g>` +
    `<circle cx='10' cy='10' r='.7' fill='#7a1c12'/></svg>`;
  return { frame, band, diaper };
}

/** 圣物匣：整张牌 100 × 142 的厚金框（斜光）、内侧暗槽、四角卷草、顶部嵌宝石的托座。 */
function reliquary() {
  const scroll = (x: number, y: number, sx: number, sy: number) =>
    `<g transform='translate(${x} ${y}) scale(${sx} ${sy})'>` +
    `<path d='M0 15C0 6 5 1.5 13 1.5' fill='none' stroke='url(#s)' stroke-width='1.5' stroke-linecap='round'/>` +
    `<path d='M13 1.5C16.5 1.5 17.5 5 15 6.4C13 7.4 11.2 5.6 12.4 4.2' fill='none' stroke='url(#s)' stroke-width='1.1' stroke-linecap='round'/>` +
    `<path d='M0 15C0 18.5 3.5 19.5 4.9 17C5.9 15 4.1 13.2 2.7 14.4' fill='none' stroke='url(#s)' stroke-width='1.1' stroke-linecap='round'/>` +
    `<path d='M3.2 3.2L6.2 4.4L4.4 6.2Z' fill='url(#s)'/>` +
    `<circle cx='7.4' cy='7.4' r='1.1' fill='url(#s)' stroke='#2a1a06' stroke-width='.3'/></g>`;
  const frame = svg("0 0 100 142",
    `<path d='M0 0H100V142H0Z M5 5V137H95V5Z' fill='url(#s)' fill-rule='evenodd'/>` +
    // 金框的倒角：外沿亮、内沿暗
    `<rect x='.6' y='.6' width='98.8' height='140.8' rx='2.4' fill='none' stroke='#fff3c8' stroke-opacity='.7' stroke-width='.5'/>` +
    `<rect x='2.4' y='2.4' width='95.2' height='137.2' fill='none' stroke='#5a3f1a' stroke-opacity='.8' stroke-width='.35'/>` +
    `<rect x='5' y='5' width='90' height='132' fill='none' stroke='#1a1206' stroke-width='.9'/>` +
    `<rect x='6.1' y='6.1' width='87.8' height='129.8' fill='none' stroke='#e6c67a' stroke-opacity='.6' stroke-width='.4'/>` +
    // 金框上的一排小珠
    `<g fill='#fff0c0' fill-opacity='.55'>${Array.from({ length: 13 }, (_, i) => `<circle cx='${f(14 + i * 6)}' cy='2.5' r='.45'/><circle cx='${f(14 + i * 6)}' cy='139.5' r='.45'/>`).join("")}` +
    `${Array.from({ length: 19 }, (_, i) => `<circle cx='2.5' cy='${f(17 + i * 6)}' r='.45'/><circle cx='97.5' cy='${f(17 + i * 6)}' r='.45'/>`).join("")}</g>` +
    scroll(6.8, 6.8, 1, 1) + scroll(93.2, 6.8, -1, 1) + scroll(6.8, 135.2, 1, -1) + scroll(93.2, 135.2, -1, -1) +
    // 顶部托座：宝石嵌在这里
    `<path d='M36 0H64L60 5.6Q50 11.5 40 5.6Z' fill='url(#s)' stroke='#1a1206' stroke-width='.6'/>`,
    GOLD_SHEEN);
  return { frame };
}

/** 塔罗：画框是 91 × 133 的洋葱顶拱（牌宽 × 0.91、1.33）；整张牌 100 × 142 的双细金线跟着拱走，拱尖一颗星。 */
function arcana() {
  const ogee = (x0: number, y0: number, w: number, h: number, rise: number, close = true) => {
    const x1 = x0 + w;
    const mid = x0 + w / 2;
    const shoulder = y0 + rise;
    return `M${f(x0)} ${f(y0 + h)}V${f(shoulder)}C${f(x0)} ${f(shoulder - rise * 0.62)} ${f(mid - w * 0.2)} ${f(y0 + rise * 0.3)} ${f(mid)} ${f(y0)}` +
      `C${f(mid + w * 0.2)} ${f(y0 + rise * 0.3)} ${f(x1)} ${f(shoulder - rise * 0.62)} ${f(x1)} ${f(shoulder)}V${f(y0 + h)}${close ? "Z" : ""}`;
  };
  const mask = svg("0 0 91 133", `<path d='${ogee(0, 0, 91, 133, 26)}' fill='#000'/>`);
  const star = (x: number, y: number, r: number) =>
    `<path d='M${x} ${f(y - r)}L${f(x + r * 0.28)} ${f(y - r * 0.28)}L${f(x + r)} ${y}L${f(x + r * 0.28)} ${f(y + r * 0.28)}L${x} ${f(y + r)}L${f(x - r * 0.28)} ${f(y + r * 0.28)}L${f(x - r)} ${y}L${f(x - r * 0.28)} ${f(y - r * 0.28)}Z' fill='url(#g)'/>`;
  const frame = svg("0 0 100 142",
    `<path d='${ogee(4.5, 4.5, 91, 133, 26, false)}' fill='none' stroke='#120c08' stroke-width='1.6'/>` +
    `<path d='${ogee(4.5, 4.5, 91, 133, 26, false)}' fill='none' stroke='url(#g)' stroke-width='.8'/>` +
    `<path d='${ogee(2.2, 2.2, 95.6, 137.6, 27.5, false)}' fill='none' stroke='url(#g)' stroke-width='.35' stroke-opacity='.8'/>` +
    `<rect x='.4' y='.4' width='99.2' height='141.2' rx='4' fill='none' stroke='url(#g)' stroke-width='.5' stroke-opacity='.7'/>` +
    star(50, 2.4, 2.6) + star(3.4, 30, 1.3) + star(96.6, 30, 1.3),
    GOLD);
  return { mask, frame };
}

/** 数值图标（遮罩用，颜色由 CSS 给）：剑、心、盾、血滴。 */
const ICONS = {
  sword: svg("0 0 24 24", `<path d='M12 .8L15.2 4.2V14.2H8.8V4.2Z M3.6 14.2H20.4V17H3.6Z M10.4 17H13.6V20.6H10.4Z' fill='#000'/><circle cx='12' cy='21.6' r='2.2' fill='#000'/>`),
  heart: svg("0 0 24 24", `<path d='M12 21.5C5 16 1.8 12.4 1.8 8.2C1.8 5 4.3 2.6 7.2 2.6C9.3 2.6 11 3.8 12 5.6C13 3.8 14.7 2.6 16.8 2.6C19.7 2.6 22.2 5 22.2 8.2C22.2 12.4 19 16 12 21.5Z' fill='#000'/>`),
  quatrefoil: svg("0 0 24 24", `<g fill='#000'><circle cx='12' cy='6.4' r='5.6'/><circle cx='12' cy='17.6' r='5.6'/><circle cx='6.4' cy='12' r='5.6'/><circle cx='17.6' cy='12' r='5.6'/><rect x='6.4' y='6.4' width='11.2' height='11.2'/></g>`),
};

export function installFrames() {
  const root = document.documentElement.style;
  const v = vitrail();
  const c = codex();
  const r = reliquary();
  const a = arcana();
  const vars: Record<string, string> = {
    "--fr-stone": url(grain(0.55, 0.85)),
    "--fr-grain": url(grain(0.28, 1.1)),
    "--fr-vitrail-mask": url(v.mask),
    "--fr-vitrail-frame": url(v.frame),
    "--fr-vitrail-glass": url(v.glass),
    "--fr-codex-frame": url(c.frame),
    "--fr-codex-band": url(c.band),
    "--fr-codex-diaper": url(c.diaper),
    "--fr-reliquary-frame": url(r.frame),
    "--fr-arcana-mask": url(a.mask),
    "--fr-arcana-frame": url(a.frame),
    "--ic-sword": url(ICONS.sword),
    "--ic-heart": url(ICONS.heart),
    "--ic-quatrefoil": url(ICONS.quatrefoil),
  };
  for (const [k, val] of Object.entries(vars)) root.setProperty(k, val);
  applyFrame(currentFrame());
}

// ───────────────────────── 卡框一览（?frames） ─────────────────────────

export interface GalleryBody { atk: number; hp: number; startHp: number; shape: AttackShape; armor: number; barrier: number }
export interface GalleryHooks {
  card(id: string | null, o: { body?: GalleryBody; equip?: string | null; dead?: boolean; cls?: string; flag?: string; down?: boolean; backText?: string }): string;
}

const HERO_IDS = ["PR3", "LU1", "SL4", "GR2", "WR1"];

function base(id: string): GalleryBody {
  const c = character(id);
  return { atk: c.atk, hp: c.hp, startHp: c.hp, shape: c.shape, armor: c.armor, barrier: c.barrier };
}

/**
 * 一页看完所有卡框：每套一节，大卡、斜放桌面上的各种状态、小卡。点“用这套”就换成它。
 * ?frames=compare 是紧凑版：每套只一行大卡，方便截一张图对比。
 */
export function showGallery(hooks: GalleryHooks) {
  const chosen = currentFrame();
  const compare = new URLSearchParams(location.search).get("frames") === "compare";
  // 一览页里每节自己带 data-frame，根元素上的去掉，免得两套规则叠在一起
  delete document.documentElement.dataset.frame;
  const hero = HERO_IDS.map((id) => hooks.card(id, {})).join("");
  const states = [
    hooks.card("EN1", { body: { ...base("EN1"), hp: 3 }, flag: "受伤" }),
    hooks.card("WR3", { equip: "E01" }),
    hooks.card("PR2", { cls: "shielded" }),
    hooks.card("SL2", { cls: "selected" }),
    hooks.card("GL2", { dead: true }),
    hooks.card(null, { backText: "布阵中…" }),
  ].join("");
  const small = CHARACTERS.slice(0, 8).map((c) => hooks.card(c.id, {})).join("");
  const tiny = CHARACTERS.slice(8, 16).map((c) => hooks.card(c.id, {})).join("");
  const sections = FRAMES.map((fr) => `
    <section class="fg-sec" id="fr-${fr.id}" data-frame="${fr.id}">
      <header class="fg-head">
        <div><h2>${fr.name}<i>${fr.latin}</i>${fr.id === chosen ? `<em class="fg-on">使用中</em>` : ""}</h2><p>${esc(fr.about)}</p></div>
        <div class="fg-btns">
          <a class="fg-btn" href="./?debug&me=PR3,LU1,SL4,WR1&frame=${fr.id}">上桌看看</a>
          <button class="fg-btn primary" data-frame-pick="${fr.id}">${fr.id === chosen ? "正在用" : "用这套"}</button>
        </div>
      </header>
      <div class="fg-row fg-hero">${hero}</div>
      <div class="fg-felt"><div class="fg-felt-in">${states}</div></div>
      <div class="fg-row fg-small">${small}</div>
      <div class="fg-row fg-tiny">${tiny}</div>
    </section>`).join("");
  const nav = FRAMES.map((fr) => `<a href="#fr-${fr.id}">${fr.name}<i>${fr.latin}</i></a>`).join("");
  const page = document.createElement("div");
  page.id = "frames";
  page.classList.toggle("compare", compare);
  page.innerHTML = `<div class="fg-top"><h1>卡框样式</h1><nav>${nav}</nav><a class="fg-btn" href="./">回到游戏 ›</a></div>${sections}`;
  document.body.appendChild(page);
  page.addEventListener("click", (ev) => {
    const b = (ev.target as HTMLElement).closest<HTMLElement>("[data-frame-pick]");
    if (!b) return;
    saveFrame(b.dataset.framePick as FrameId);
    page.remove();
    showGallery(hooks);
    document.getElementById(`fr-${b.dataset.framePick}`)?.scrollIntoView();
  });
}
