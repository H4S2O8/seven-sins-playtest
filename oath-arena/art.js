import { UNITS } from "./content.js";
// Replace a manifest entry with an image or spritesheet; gameplay never depends on art.
export const ASSETS = {
  background: "./assets/arena.webp",
  portraits: {},
  sprites: {},
  effects: {},
  audio: {},
};
const atlasRects = {
  knight: [0, 0, 347, 416],
  blade: [348, 0, 287, 416],
  rider: [636, 0, 328, 416],
  priest: [975, 0, 279, 417],
  colossus: [0, 418, 347, 418],
  archer: [345, 418, 296, 418],
  bell: [642, 418, 312, 418],
  hook: [962, 417, 292, 423],
  cannon: [0, 891, 350, 360],
  mage: [346, 836, 297, 418],
  lancer: [650, 838, 272, 416],
  banner: [940, 838, 314, 416],
};
for (const u of UNITS) {
  const rect = atlasRects[u.art];
  ASSETS.portraits[u.id] = {
    url: "./assets/units.webp",
    rect,
    atlasWidth: 1254,
    atlasHeight: 1254,
  };
  ASSETS.sprites[u.id] = {
    url: "./assets/units.webp",
    rect,
    width: 62 + u.pop * 10,
    height: 75 + u.pop * 12,
  };
}
const images = new Map();
function getImage(src) {
  if (!src) return null;
  if (!images.has(src)) {
    const im = new Image();
    im.addEventListener("load", () =>
      window.dispatchEvent(new Event("oath-art-ready")),
    );
    im.src = src;
    images.set(src, im);
  }
  const im = images.get(src);
  return im.complete && im.naturalWidth ? im : null;
}
const paths = {
  knight:
    "M28 16L40 10 52 16 54 35 46 43 48 70 58 88 43 90 38 67 34 90 18 88 27 69 25 46 14 58 6 49 16 28ZM24 30L9 32 10 60 24 68 36 59 35 34Z",
  blade:
    "M29 11L43 8 51 24 43 36 48 51 59 77 48 89 35 65 27 91 17 88 24 58 18 40 9 66 3 64 17 26ZM55 8L61 5 60 66 55 73Z",
  rider:
    "M25 28L39 19 54 31 47 47 54 62 68 77 62 88 44 75 32 61 24 86 9 86 17 67 11 54 4 51 5 39 16 34ZM35 7L49 7 52 21 39 26Z",
  priest:
    "M25 23Q23 1 39 4Q56 4 53 24L47 36 61 88 13 88 27 36ZM5 15L9 15 10 90 5 90ZM0 26L17 26 17 32 0 32Z",
  colossus:
    "M20 17L48 12 58 30 53 48 66 55 67 76 55 77 47 63 49 90 32 90 28 66 21 90 6 90 11 64 4 50 6 28ZM60 4L75 4 78 22 70 30 56 24Z",
  archer:
    "M27 8L42 8 49 24 41 35 49 55 46 84 36 90 31 59 23 89 13 84 19 56 15 37ZM58 13Q83 48 58 79L62 51 62 43ZM29 42L77 43 83 48 77 52 29 51Z",
  bell: "M23 7L42 7 48 23 42 36 47 61 43 90 32 90 28 66 20 89 9 88 17 51 9 31ZM40 34Q71 18 77 64L81 70 38 70 42 64ZM55 70L64 70 64 80 55 80Z",
  hook: "M27 10L41 10 46 25 39 35 46 54 44 88 32 88 28 65 19 88 8 87 15 53 12 36ZM39 45L63 34 70 40 76 56 73 69 65 73 61 68 68 59 63 46 43 57Z",
  cannon:
    "M5 53L12 38 52 37 66 48 64 71 14 72ZM33 35L62 4 74 13 49 45ZM9 68L24 68 25 87 8 87ZM49 68L65 68 71 87 51 87Z",
  mage: "M23 25L37 3 55 26 46 36 64 90 7 90 24 36ZM3 18L10 18 10 80 3 80ZM1 9L9 0 18 9 10 20Z",
  lancer:
    "M23 10L37 8 46 22 39 36 48 50 45 88 31 88 28 65 20 88 9 87 16 51 13 35ZM58 0L65 17 62 24 62 92 57 92 57 24 53 17Z",
  banner:
    "M22 9L36 7 44 23 38 35 44 56 42 89 29 89 25 63 18 89 7 89 14 53 11 34ZM55 0L59 0 59 93 55 93ZM59 7L84 10 74 24 85 36 59 32Z",
};
export function portrait(u, size = 120) {
  const p = ASSETS.portraits[u.id];
  if (p && typeof p === "object") {
    return `<svg viewBox="${p.rect.join(" ")}" width="${size}" height="${size}" aria-hidden="true"><image href="${p.url}" width="${p.atlasWidth}" height="${p.atlasHeight}"/></svg>`;
  }
  if (p)
    return `<img src="${p}" alt="${u.name}" width="${size}" height="${size}">`;
  const v = (Number(u.id?.slice(1)) || 1) % 5,
    colors = ["#8ed6dd", "#cfb574", "#b993d3", "#b7c5d6", "#ce8588"];
  return `<svg viewBox="0 0 100 104" width="${size}" height="${size}" aria-hidden="true"><circle cx="48" cy="49" r="39" fill="none" stroke="${colors[v]}" stroke-opacity=".18"/><path d="M7 90L90 90M48 4L48 97M9 49L91 49" stroke="${colors[v]}" opacity=".09"/><path d="${paths[u.art] || paths.knight}" transform="translate(8 5)" fill="#111c2b" stroke="${colors[v]}" stroke-width="1.5"/><path d="M36 22L43 23" stroke="#faf0c3" stroke-width="2.5"/><circle cx="49" cy="52" r="4" fill="${colors[v]}" opacity=".5"/></svg>`;
}
function line(ctx, x, y, tx, ty, color, w = 1) {
  ctx.strokeStyle = color;
  ctx.lineWidth = w;
  ctx.beginPath();
  ctx.moveTo(x, y);
  ctx.lineTo(tx, ty);
  ctx.stroke();
}
export function drawArena(ctx, w, h, time = 0) {
  ctx.clearRect(0, 0, w, h);
  const bg = getImage(ASSETS.background);
  if (bg) {
    ctx.drawImage(bg, 0, 0, w, h);
    ctx.fillStyle = "#090e1838";
    ctx.fillRect(0, 0, w, h);
    ctx.fillStyle = "#d7ba7809";
    ctx.fillRect(320, 76, 320, h - 116);
    ctx.setLineDash([5, 9]);
    line(ctx, 245, 76, 245, h - 40, "#8ddce74a");
    line(ctx, 320, 76, 320, h - 40, "#d7ba7888");
    line(ctx, 640, 76, 640, h - 40, "#d7ba7888");
    line(ctx, 715, 76, 715, h - 40, "#e48c984a");
    ctx.setLineDash([]);
    ctx.textAlign = "center";
    ctx.font = "11px sans-serif";
    for (const [x, t, c] of [
      [156, "己方后排", "#9adddf"],
      [332, "己方前排", "#9adddf"],
      [628, "敌方前排", "#e49aa5"],
      [804, "敌方后排", "#e49aa5"],
    ]) {
      ctx.fillStyle = "#080d15dd";
      ctx.fillRect(x - 38, h - 27, 76, 21);
      ctx.fillStyle = c;
      ctx.fillText(t, x, h - 12);
    }
    return;
  }
  let g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, "#080e19");
  g.addColorStop(1, "#17202a");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  ctx.save();
  ctx.translate(w / 2, 0);
  ctx.strokeStyle = "#536077";
  ctx.globalAlpha = 0.15;
  for (let r = 170; r < 570; r += 70) {
    ctx.beginPath();
    ctx.arc(0, 35, r, 0, Math.PI);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  for (let i = -6; i <= 6; i++) {
    const x = i * 91;
    ctx.fillStyle = i % 2 ? "#0b1320" : "#0d1724";
    ctx.fillRect(x - 20, 0, 40, 99 + Math.abs(i) * 8);
    ctx.beginPath();
    ctx.moveTo(x - 28, 0);
    ctx.lineTo(x, 27);
    ctx.lineTo(x + 28, 0);
    ctx.fill();
  }
  ctx.restore();
  ctx.fillStyle = "#18232e";
  ctx.beginPath();
  ctx.moveTo(30, 69);
  ctx.lineTo(w - 30, 69);
  ctx.lineTo(w - 5, h - 30);
  ctx.lineTo(5, h - 30);
  ctx.closePath();
  ctx.fill();
  for (let y = 85; y < h - 25; y += 39)
    line(ctx, 15, y, w - 15, y, "#64708018");
  for (let x = 32; x < w; x += 56)
    line(ctx, x, 70, (x - w / 2) * 1.02 + w / 2, h - 30, "#64708015");
  ctx.fillStyle = "#bda66607";
  ctx.fillRect(320, 69, 320, h - 99);
  ctx.setLineDash([4, 9]);
  line(ctx, 320, 69, 320, h - 30, "#c9b27644");
  line(ctx, 640, 69, 640, h - 30, "#c9b27644");
  line(ctx, 480, 69, 480, h - 30, "#d0c09335");
  ctx.setLineDash([]);
  ctx.strokeStyle = "#baa87822";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.ellipse(w / 2, h / 2 + 16, 127, 92, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.beginPath();
  ctx.ellipse(w / 2, h / 2 + 16, 119, 86, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.fillStyle = "#a4916144";
  ctx.font = "12px Georgia";
  ctx.textAlign = "center";
  ctx.fillText("I U D I C I U M", w / 2, h / 2 + 20);
  ctx.fillStyle = "#90cbd566";
  ctx.font = "11px sans-serif";
  ctx.fillText("己方后排", 156, h - 13);
  ctx.fillText("己方前排", 332, h - 13);
  ctx.fillStyle = "#ce8a9966";
  ctx.fillText("敌方前排", 628, h - 13);
  ctx.fillText("敌方后排", 804, h - 13);
  for (let i = 0; i < 18; i++) {
    const x = (i * 157 + time * 7) % w,
      y = 50 + ((i * 73) % 330);
    ctx.fillStyle = `rgba(216,194,132,${0.09 + 0.08 * Math.sin(time + i)})`;
    ctx.fillRect(x, y, 1.6, 1.6);
  }
}
export function drawEntity(ctx, e, time) {
  if (e.hp <= 0) {
    ctx.globalAlpha = 0.15;
    ctx.fillStyle = e.side ? "#bf7984" : "#75c9d7";
    ctx.beginPath();
    ctx.ellipse(e.x, e.y + 14, 22, 7, 0, 0, Math.PI * 2);
    ctx.fill();
    ctx.globalAlpha = 1;
    return;
  }
  const scale = 0.45 + e.pop * 0.095,
    im = getImage(ASSETS.sprites[e.unitId]?.url || ASSETS.sprites[e.unitId]);
  ctx.save();
  ctx.translate(e.x, e.y);
  ctx.fillStyle = "#0006";
  ctx.beginPath();
  ctx.ellipse(0, 16, (20 * scale) / 0.6, 7, 0, 0, Math.PI * 2);
  ctx.fill();
  const walk = e.moving
    ? Math.sin(time * 12) * 2
    : Math.sin(time * 2 + e.x) * 0.7;
  ctx.translate(0, walk);
  const col = e.side ? "#e48c98" : "#8ddce7";
  ctx.strokeStyle = col;
  ctx.globalAlpha = 0.7;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.ellipse(0, 17, 21, 7, 0, 0, Math.PI * 2);
  ctx.stroke();
  ctx.globalAlpha = 1;
  if (e.marked) {
    ctx.strokeStyle = "#dfc17f";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.ellipse(0, 17, 25, 10, 0, 0, Math.PI * 2);
    ctx.stroke();
    ctx.fillStyle = "#ddc58b";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("◆", 0, -56 * scale);
  }
  if (e.shield > 0) {
    ctx.strokeStyle = "#ebdbaaaa";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.ellipse(0, -12, 27 + e.shield * 2, 38, 0, 0, Math.PI * 2);
    ctx.stroke();
  }
  if (e.tags.includes("siege") && e.still > 1.2) {
    ctx.strokeStyle = "#d2a76899";
    ctx.setLineDash([2, 4]);
    ctx.beginPath();
    ctx.arc(0, 8, 33, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);
  }
  if (im) {
    const entry = ASSETS.sprites[e.unitId];
    ctx.save();
    ctx.scale(e.face < 0 ? -1 : 1, 1);
    if (e.flash > 0) ctx.filter = "brightness(1.8)";
    const attackAge = time - (e.attackTime ?? -99);
    if (attackAge >= 0 && attackAge < 0.25)
      ctx.translate(Math.sin((attackAge / 0.25) * Math.PI) * 6, 0);
    if (typeof entry === "object" && entry.rect) {
      const [sx, sy, sw, sh] = entry.rect,
        width = entry.width || 70,
        height = entry.height || 90;
      ctx.drawImage(im, sx, sy, sw, sh, -width / 2, 18 - height, width, height);
    } else if (
      typeof entry === "object" &&
      entry.frameWidth &&
      entry.frameHeight
    ) {
      const state =
        time - (e.attackTime ?? -99) < 0.3
          ? "attack"
          : e.moving
            ? "move"
            : "idle";
      const anim = entry.animations?.[state] || { row: 0, frames: 1, fps: 1 };
      const frame = Math.floor(time * (anim.fps || 8)) % (anim.frames || 1);
      const width = entry.width || 70,
        height = entry.height || 90;
      ctx.drawImage(
        im,
        frame * entry.frameWidth,
        (anim.row || 0) * entry.frameHeight,
        entry.frameWidth,
        entry.frameHeight,
        -width / 2,
        18 - height,
        width,
        height,
      );
    } else ctx.drawImage(im, -30, -60, 60, 80);
    ctx.restore();
  } else {
    ctx.save();
    ctx.scale(scale * (e.face || 1), scale);
    ctx.translate(-40, -65);
    ctx.fillStyle = e.flash > 0 ? "#f8e3b8" : "#18222d";
    ctx.strokeStyle = col;
    ctx.lineWidth = 1.8;
    const path = new Path2D(paths[e.art] || paths.knight);
    ctx.fill(path);
    ctx.stroke(path);
    ctx.fillStyle = "#f2e5bc";
    ctx.fillRect(29, 20, 10, 3);
    ctx.restore();
  }
  const bw = 38 + e.pop * 5;
  ctx.fillStyle = "#05080d";
  ctx.fillRect(-bw / 2, 23, bw, 5);
  ctx.fillStyle = col;
  ctx.fillRect(-bw / 2, 23, bw * Math.max(0, e.hp / e.maxHp), 4);
  ctx.font = "10px sans-serif";
  ctx.textAlign = "center";
  ctx.fillStyle = "#d4d8de";
  ctx.fillText(e.name, 0, 41);
  if (e.mode === "stand") {
    ctx.fillStyle = "#c4b887";
    ctx.fillText("▰", 0, 52);
  }
  ctx.restore();
}
export function drawBattle(ctx, b) {
  drawArena(ctx, 960, 430, b.time);
  for (const e of [...b.entities].sort((a, c) => a.y - c.y))
    drawEntity(ctx, e, b.time);
  for (const fx of b.events) {
    const age = b.time - fx.t;
    if (age > 0.6) continue;
    const a = 1 - age / 0.6;
    ctx.save();
    ctx.globalAlpha = a;
    const col = fx.side ? "#ef92a5" : "#94eced";
    const replacement = ASSETS.effects[fx.kind] || ASSETS.effects[fx.type];
    const fxImage = getImage(
      typeof replacement === "string" ? replacement : replacement?.url,
    );
    if (fxImage) {
      const size = replacement?.size || 100;
      ctx.drawImage(
        fxImage,
        (fx.tx ?? fx.x) - size / 2,
        (fx.ty ?? fx.y) - size / 2,
        size,
        size,
      );
      ctx.restore();
      continue;
    }
    if (["bolt", "beam", "pull", "charge", "push", "slash"].includes(fx.type)) {
      ctx.shadowColor = col;
      ctx.shadowBlur = 12;
      line(
        ctx,
        fx.x,
        fx.y - 12,
        fx.tx,
        fx.ty - 12,
        fx.type === "beam" ? "#9de4ab" : col,
        fx.type === "charge" ? 5 : fx.kind === "pierce" ? 3 : 1.6,
      );
      if (fx.kind === "splash") {
        ctx.strokeStyle = "#e4b276";
        ctx.beginPath();
        ctx.arc(fx.tx, fx.ty, 12 + age * 85, 0, Math.PI * 2);
        ctx.stroke();
      }
    }
    if (["shield", "ward", "death"].includes(fx.type)) {
      ctx.strokeStyle = fx.type === "death" ? col : "#ead598";
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc(fx.x, fx.y - 12, 15 + age * 60, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (fx.type === "hit" || fx.type === "heal") {
      ctx.fillStyle = fx.type === "heal" ? "#a8e5ba" : "#eadfcf";
      ctx.font = "bold 12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(
        (fx.type === "heal" ? "+" : "−") + fx.n,
        fx.x,
        fx.y - 40 - age * 25,
      );
    }
    ctx.restore();
  }
}
