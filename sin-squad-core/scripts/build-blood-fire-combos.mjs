import { readFile, writeFile } from "node:fs/promises";

const markdown = await readFile(new URL("../docs/blood-fire-forgotten-combos.md", import.meta.url), "utf8");
let chapter = "";
const routes = [];
for (const line of markdown.split(/\r?\n/)) {
  const heading = line.match(/^## (C\d{2})\s+(.+)$/);
  if (heading) chapter = heading[1];
  const row = line.match(/^\|\s*(\d{3})\s+([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|\s*$/);
  if (!row) continue;
  const [, id, name, members, condition] = row;
  const routeChapter = Number(id) >= 201 ? `C${Number(id) - 175}` : chapter;
  const attackers = ({ "201": ["B05", "F05"], "202": ["B05", "N01"], "203": ["B02", "N01"], "204": ["B05", "B02", "N01"] })[id] ?? [];
  routes.push({ id, name: name.trim(), chapter: routeChapter, members: members.match(/[BFNPE]\d{2}/g) ?? [], attackers, condition: condition.trim() });
}
  if (routes.length !== 204 || new Set(routes.map(route => route.id)).size !== 204 || new Set(routes.map(route => route.name)).size !== 204) {
  throw new Error(`Expected 204 unique named routes, found ${routes.length}`);
}
const output = `/** Generated from docs/blood-fire-forgotten-combos.md. Run npm run build:blood-fire-combos. */\nexport type ComboRoute = { id: string; name: string; chapter: string; members: string[]; attackers: string[]; condition: string };\nexport const COMBO_ROUTES: ComboRoute[] = ${JSON.stringify(routes, null, 2)};\n`;
await writeFile(new URL("../src/blood-fire/combo-routes.ts", import.meta.url), output);
console.log(`Generated ${routes.length} named routes`);
