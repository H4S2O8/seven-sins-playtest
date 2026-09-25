import type { Sin } from "../src/types.js";
import { SIN_COLOR } from "./text.js";

/**
 * 七罪的纹章：七芒星（{7/3} 星形）套在双环里，七个角上各嵌一颗罪色宝石，中间写 VII。
 * 宝石按大格里高利的七罪次序排：傲慢在顶上，顺时针贪婪、色欲、嫉妒、暴食、愤怒、怠惰。
 * 生成一张 SVG，作为 CSS 变量 --sigil 给牌背、长条牌背、标题页用。
 */

/** 七罪的拉丁名（卡面水印、详情页、装饰文字）。 */
export const SIN_LATIN: Record<Sin, string> = {
  傲慢: "SUPERBIA",
  贪婪: "AVARITIA",
  色欲: "LUXURIA",
  嫉妒: "INVIDIA",
  暴食: "GULA",
  愤怒: "IRA",
  怠惰: "ACEDIA",
};

const ORDER: Sin[] = ["傲慢", "贪婪", "色欲", "嫉妒", "暴食", "愤怒", "怠惰"];

const pt = (r: number, i: number, n = 7, turn = 0) => {
  const a = -Math.PI / 2 + ((i + turn) * 2 * Math.PI) / n;
  return [r * Math.cos(a), r * Math.sin(a)].map((v) => v.toFixed(2)).join(" ");
};

/** {7/k} 星形的路径。 */
const star = (r: number, k: number) => `M${Array.from({ length: 7 }, (_, i) => pt(r, (i * k) % 7)).join("L")}Z`;

export function sigilSvg(): string {
  const gems = ORDER.map((sin, i) => {
    const [x, y] = pt(84, i).split(" ").map(Number);
    return `<circle cx='${x}' cy='${y}' r='8.5' fill='${SIN_COLOR[sin]}' stroke='url(#g)' stroke-width='2.2'/>` +
      `<circle cx='${(x - 2.6).toFixed(2)}' cy='${(y - 2.6).toFixed(2)}' r='2.6' fill='#fff' fill-opacity='.55'/>`;
  }).join("");
  const dots = Array.from({ length: 21 }, (_, i) => {
    const [x, y] = pt(93.5, i, 21, 0.5).split(" ");
    return `<circle cx='${x}' cy='${y}' r='1.4'/>`;
  }).join("");
  return `<svg xmlns='http://www.w3.org/2000/svg' viewBox='-100 -100 200 200'>` +
    `<defs><linearGradient id='g' x1='0' y1='0' x2='0' y2='1'><stop offset='0' stop-color='#fff0c0'/><stop offset='.45' stop-color='#d9b25f'/><stop offset='1' stop-color='#8a6424'/></linearGradient>` +
    `<radialGradient id='d'><stop offset='0' stop-color='#4a1426'/><stop offset='1' stop-color='#14060c'/></radialGradient></defs>` +
    `<circle r='97' fill='none' stroke='url(#g)' stroke-width='3'/>` +
    `<circle r='90' fill='none' stroke='url(#g)' stroke-width='1.1' stroke-opacity='.85'/>` +
    `<g fill='#d9b25f'>${dots}</g>` +
    `<path d='${star(84, 2)}' fill='none' stroke='#d9b25f' stroke-opacity='.35' stroke-width='1.1'/>` +
    `<path d='${star(84, 3)}' fill='none' stroke='url(#g)' stroke-width='3.2' stroke-linejoin='round'/>` +
    `<circle r='31' fill='url(#d)' stroke='url(#g)' stroke-width='2.2'/>` +
    `<text y='9.5' text-anchor='middle' font-family='Georgia, Palatino, serif' font-size='27' font-weight='bold' letter-spacing='1' fill='url(#g)'>VII</text>` +
    gems +
    `</svg>`;
}

/** 把纹章挂到根元素的 --sigil 上。 */
export function installSigil() {
  document.documentElement.style.setProperty("--sigil", `url("data:image/svg+xml,${encodeURIComponent(sigilSvg())}")`);
}
