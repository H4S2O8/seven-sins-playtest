// Continuous, composable deformation of the actual actor texture, not a color filter.
// Each desire contributes independently; no 100-frame sheet or hard form swaps.
export function drawBeing(
  ctx,
  atlas,
  e,
  index,
  x,
  y,
  height,
  time,
  fx,
  rows = 2,
  columns = 4,
) {
  const sins = e.sins || {},
    v = (id) => (sins[id] || 0) / 100,
    cw = atlas.width / columns,
    ch = atlas.height / rows,
    sx = (index % columns) * cw,
    sy = Math.floor(index / columns) * ch,
    w = (height * cw) / ch;
  const crouch = v("sloth") * 0.22,
    lean = v("wrath") * 0.17,
    breath = Math.sin(time * 2.3) * 0.005,
    bodyHeight = height * (1 - crouch),
    stride = e.moving ? Math.sin(time * 9) : 0;
  ctx.save();
  const opacity=ctx.globalAlpha;
  ctx.translate(x, y + height * 0.06);
  if (e.flip) ctx.scale(-1, 1);
  for (let band = 0; band < 32; band++) {
    const t = band / 32,
      waist = Math.exp(-(((t - 0.52) / 0.18) ** 2)),
      shoulder = Math.exp(-(((t - 0.33) / 0.16) ** 2)),
      width =
        1 +
        v("gluttony") * 0.5 * waist +
        v("pride") * 0.32 * shoulder +
        v("greed") * 0.13 * shoulder +
        breath,
      shift =
        (1 - t) * height * lean +
        (t > 0.65 ? stride * (t - 0.65) * 4 : stride * 0.4);
    ctx.drawImage(
      atlas,
      sx,
      sy + t * ch,
      cw,
      ch / 32 + 0.5,
      (-w * width) / 2 + shift,
      -bodyHeight + t * bodyHeight,
      w * width,
      bodyHeight / 32 + 0.5,
    );
  }
  if (v("envy") > 0.02) {
    ctx.globalAlpha = opacity*v("envy") * 0.5;
    for (const direction of [-1, 1])
      ctx.drawImage(
        atlas,
        sx,
        sy,
        cw,
        ch * 0.3,
        -w / 2 + direction * v("envy") * height * 0.08,
        -bodyHeight - height * 0.015,
        w,
        bodyHeight * 0.3,
      );
    ctx.globalAlpha = opacity;
  }
  if (v("greed") > 0.05) {
    ctx.globalAlpha = opacity*v("greed") * 0.7;
    for (const side of [-1, 1]) {
      ctx.save();
      ctx.translate(side * height * 0.09, -bodyHeight * 0.42);
      ctx.rotate(side * (0.15 + v("greed") * 0.3));
      ctx.drawImage(
        atlas,
        sx + cw * (side < 0 ? 0.14 : 0.56),
        sy + ch * 0.3,
        cw * 0.3,
        ch * 0.36,
        -w * 0.15,
        -bodyHeight * 0.2,
        w * 0.3,
        bodyHeight * 0.36,
      );
      ctx.restore();
    }
    ctx.globalAlpha = opacity;
  }
  if (v("gluttony") > 0.03 && fx) {
    const cellW = fx.width / 4,
      cellH = fx.height / 2,
      size = height * (0.13 + 0.26 * v("gluttony"));
    ctx.globalAlpha = opacity*Math.min(1, v("gluttony") * 2);
    ctx.drawImage(
      fx,
      0,
      0,
      cellW,
      cellH,
      -size / 2,
      -bodyHeight * 0.65,
      size,
      size,
    );
    ctx.globalAlpha = opacity;
  }
  ctx.restore();
}

// Align occupied scanlines before interpolation. Crossfading unaligned sprites
// produces two heads/feet instead of a single changing silhouette.
const morphFrames = new WeakMap();
function alignedFrame(atlas, cell, columns) {
  let frames = morphFrames.get(atlas);
  if (!frames) morphFrames.set(atlas, frames = new Map());
  const key = `${columns}:${cell}`;
  if (frames.has(key)) return frames.get(key);
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 192;
  const g = canvas.getContext('2d'), cw = atlas.width / columns, ch = atlas.height / 2;
  g.drawImage(atlas, cell % columns * cw, Math.floor(cell / columns) * ch, cw, ch, 0, 0, 192, 192);
  const pixels = g.getImageData(0, 0, 192, 192), spans = [];
  for (let y = 0; y < 192; y++) {
    let left = 192, right = -1;
    for (let x = 0; x < 192; x++) if (pixels.data[(y * 192 + x) * 4 + 3] > 24) {left = Math.min(left, x); right = x;}
    spans.push({left, right});
  }
  const occupied = spans.map((s, y) => s.right >= s.left ? y : -1).filter(y => y >= 0);
  const frame = {pixels, spans, top: occupied[0] ?? 0, bottom: occupied.at(-1) ?? 191};
  frames.set(key, frame); return frame;
}
let blendCanvas;
const morphCache = new Map();
function silhouetteMorph(a, b, fraction, key) {
  if (morphCache.has(key)) return morphCache.get(key);
  const canvas = document.createElement('canvas'); canvas.width = canvas.height = 192;
  const g = canvas.getContext('2d'), image = g.createImageData(192, 192), mix = (x, y) => x + (y - x) * fraction;
  const top = Math.round(mix(a.top, b.top)), bottom = Math.round(mix(a.bottom, b.bottom));
  for (let y = top; y <= bottom; y++) {
    const t = (y - top) / Math.max(1, bottom - top), ay = Math.round(a.top + t * (a.bottom - a.top)), by = Math.round(b.top + t * (b.bottom - b.top));
    const sa = a.spans[ay], sb = b.spans[by];
    if (sa.right < sa.left || sb.right < sb.left) continue;
    const left = Math.round(mix(sa.left, sb.left)), right = Math.round(mix(sa.right, sb.right));
    for (let x = left; x <= right; x++) {
      const u = (x - left) / Math.max(1, right - left), ai = (ay * 192 + Math.round(sa.left + u * (sa.right - sa.left))) * 4, bi = (by * 192 + Math.round(sb.left + u * (sb.right - sb.left))) * 4, out = (y * 192 + x) * 4;
      const aa = a.pixels.data[ai + 3] / 255, ba = b.pixels.data[bi + 3] / 255, alpha = mix(aa, ba);
      for (let c = 0; c < 3; c++) image.data[out + c] = alpha ? mix(a.pixels.data[ai + c] * aa, b.pixels.data[bi + c] * ba) / alpha : 0;
      image.data[out + 3] = alpha * 255;
    }
  }
  g.putImageData(image, 0, 0);
  if (morphCache.size > 420) morphCache.delete(morphCache.keys().next().value);
  morphCache.set(key, canvas); return canvas;
}
export function drawMutant(ctx,atlases,e,index,x,y,height,time){
 const primary=Object.keys(e.sins||{}).filter(id=>atlases['mutation-'+id]).sort((a,b)=>e.sins[b]-e.sins[a])[0],value=e.sins?.[primary]||0;
 if(value<=0){drawBeing(ctx,atlases.actors,e,index,x,y,height,time,atlases.fx);return;}
 const bounds=[0,20,40,60,75,90,100],lower=Math.min(5,bounds.findIndex((n,i)=>i<6&&value>=n&&value<bounds[i+1]));
 const lo=lower<0?5:lower,hi=Math.min(5,lo+1),fraction=lo===hi?0:(value-bounds[lo])/(bounds[lo+1]-bounds[lo]);
 const frame = n => alignedFrame(n===0?atlases.actors:atlases['mutation-'+primary], n===0?index:n, n===0?4:3);
 blendCanvas = silhouetteMorph(frame(lo),frame(hi),Math.round(fraction*100)/100,`${primary}:${index}:${lo}:${Math.round(fraction*100)}`);
 const secondary={...e,sins:{...e.sins,[primary]:0}};
 drawBeing(ctx,blendCanvas,secondary,0,x,y,height,time,atlases.fx,1,1);
}
