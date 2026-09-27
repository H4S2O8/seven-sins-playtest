/** Shared physical card shell: both game modes use the same 3D edges, faces and lighting. */
export function cardShell(o: {
  classes: string;
  attributes?: string;
  front: string;
  back?: string;
  extras?: string;
}) {
  return `<div class="${o.classes}" ${o.attributes ?? ""}><div class="shade"></div><div class="lift"><div class="flip"><i class="edge top"></i><i class="edge bottom"></i><i class="edge left"></i><i class="edge right"></i><div class="face front">${o.front}</div><div class="face back"><i class="sheen"></i><i class="gloss"></i>${o.back ?? ""}</div></div>${o.extras ?? ""}</div></div>`;
}
