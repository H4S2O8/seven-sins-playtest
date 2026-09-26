/**
 * 鼠标悬停的牌：像 Steam 集换式卡牌那样朝鼠标侧过去，牌面上的反光（烫金、光油、高光）跟着这个角度走。
 *
 * - 鼠标在牌的哪个位置，牌就往那边侧（和 tilt.ts 的方向一致），光落在鼠标所在的位置。
 * - 旋转用独立的 rotate 属性（绕一根斜轴转一个角度），不碰 .lift 的 transform，
 *   所以桌上、手牌扇形、牌池、市场里各自的抬起动画都照旧，只是多了这一下侧身。
 * - 悬停中的牌带 fx-lit class（morph 会保留 fx- 开头的 class），样式里据此把反光层打开。
 * - 没被悬停的牌是平放的，只有纸面纹理和一层静止的顶光。触屏没有悬停，就一直是平放的样子。
 * - 详情大卡（.big-card 里）自己晃、自己跟鼠标（style.css 的 light-idle 和 tilt.ts），这里不管。
 *
 * morph 每次重画会把牌上多出来的 style 抹掉，所以重画之后要调一次 relight 把悬停那张补回来。
 */

/** 最大侧身角度（鼠标在牌边上时）。牌角压下去的深度要小于悬停时额外抬起的高度（style.css 的 --hz），否则会沉进桌面。 */
const MAX_TILT = 12;

let hovered: HTMLElement | null = null;
let pointer = { x: 0, y: 0 };

const own = (el: Element) => !el.closest(".big-card");

function clear(card: HTMLElement | null) {
  if (!card) return;
  card.classList.remove("fx-lit");
  for (const p of ["--fx", "--fy", "--hrot"]) card.style.removeProperty(p);
}

function follow(card: HTMLElement) {
  const r = card.getBoundingClientRect();
  if (!r.width) return;
  const x = Math.min(1, Math.max(0, (pointer.x - r.left) / r.width));
  const y = Math.min(1, Math.max(0, (pointer.y - r.top) / r.height));
  const ry = (x - 0.5) * 2 * MAX_TILT;
  const rx = -(y - 0.5) * 2 * MAX_TILT;
  const angle = Math.hypot(rx, ry);
  card.classList.add("fx-lit");
  card.style.setProperty("--fx", `${(x * 100).toFixed(1)}%`);
  card.style.setProperty("--fy", `${(y * 100).toFixed(1)}%`);
  // rotateX(rx) 接 rotateY(ry) 在小角度下约等于绕 (rx, ry, 0) 这根轴转 √(rx²+ry²)
  card.style.setProperty("--hrot", angle < 0.01 ? "0deg" : `${rx.toFixed(3)} ${ry.toFixed(3)} 0 ${angle.toFixed(2)}deg`);
}

/** 重画之后把悬停那张牌的角度和光补回来（morph 会抹掉牌上的 style）。 */
export function relight() {
  if (!hovered) return;
  if (hovered.isConnected) follow(hovered);
  else hovered = null;
}

export function installLight() {
  document.addEventListener("pointermove", (ev) => {
    if (ev.pointerType !== "mouse") return;
    pointer = { x: ev.clientX, y: ev.clientY };
    const card = (ev.target as HTMLElement | null)?.closest?.<HTMLElement>(".card.lit") ?? null;
    const next = card && own(card) && !card.hasAttribute("data-fx") ? card : null;
    if (next !== hovered) { clear(hovered); hovered = next; }
    if (next) follow(next);
  }, { passive: true });
  const leave = () => { clear(hovered); hovered = null; };
  document.addEventListener("pointerleave", leave);
  // 按下（可能开始拖牌）时先放平；再动一下鼠标又会侧过来
  document.addEventListener("pointerdown", leave);
}
