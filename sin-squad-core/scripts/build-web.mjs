// 把网页 demo 打包成纯静态文件，输出到仓库根目录的 sin-squad-v3/（GitHub Pages 直接托管）。
import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const web = join(root, "web");
const out = join(root, "..", "sin-squad-v3");
await mkdir(out, { recursive: true });

const result = await build({
  entryPoints: [join(web, "main.ts")],
  bundle: true,
  format: "esm",
  target: "es2020",
  minify: true,
  charset: "utf8",
  legalComments: "none",
  write: false,
});
const js = result.outputFiles[0].contents;
const css = await readFile(join(web, "style.css"));
const version = createHash("sha256").update(js).update(css).digest("hex").slice(0, 10);
const html = (await readFile(join(web, "index.html"), "utf8")).replaceAll("__VERSION__", version);

await writeFile(join(out, "app.js"), js);
await writeFile(join(out, "style.css"), css);
await writeFile(join(out, "index.html"), html);
console.log(`已输出到 ${out}（版本 ${version}，app.js ${(js.length / 1024).toFixed(1)} KB）`);
