// 把网页 demo 打包成纯静态文件，输出到仓库根目录的 sin-squad-v3/（不进 git；GitHub Actions 在 main 上打包后发布到 Pages）。
import { execSync } from "node:child_process";
import { createHash } from "node:crypto";
import { copyFile, mkdir, readdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { build } from "esbuild";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const web = join(root, "web");
const out = join(root, "..", "sin-squad-v3");
await mkdir(out, { recursive: true });

// 人物立绘：web/art/<人物编号>.webp，打包时把有立绘的编号告诉页面
const artDir = join(web, "art");
const artFiles = (await readdir(artDir).catch(() => [])).filter((f) => f.endsWith(".webp"));
const artIds = artFiles.map((f) => f.replace(/\.webp$/, ""));

// 版本号：package.json 版本的前两位；构建号：提交日期（北京时间）· 提交号，没有 git 时写“本地”
const pkg = JSON.parse(await readFile(join(root, "package.json"), "utf8"));
const gameVersion = `v${pkg.version.split(".").slice(0, 2).join(".")}`;
const git = (args) => execSync(`git ${args}`, { cwd: root, env: { ...process.env, TZ: "Asia/Shanghai" } }).toString().trim();
let buildId = "本地";
try { buildId = `${git("log -1 --format=%cd --date=format-local:%m-%d")} · ${git("rev-parse --short=7 HEAD")}`; } catch { /* 不在 git 仓库里 */ }

const result = await build({
  entryPoints: [join(web, "main.ts")],
  bundle: true,
  format: "esm",
  target: "es2020",
  minify: true,
  charset: "utf8",
  legalComments: "none",
  write: false,
  define: { __ART_IDS__: JSON.stringify(artIds), __GAME_VERSION__: JSON.stringify(gameVersion), __BUILD__: JSON.stringify(buildId) },
});
const js = result.outputFiles[0].contents;
const css = await readFile(join(web, "style.css"));
const version = createHash("sha256").update(js).update(css).digest("hex").slice(0, 10);
const html = (await readFile(join(web, "index.html"), "utf8")).replaceAll("__VERSION__", version).replaceAll("__GAME_VERSION__", gameVersion);

await writeFile(join(out, "app.js"), js);
await writeFile(join(out, "style.css"), css);
await writeFile(join(out, "index.html"), html);
await mkdir(join(out, "art"), { recursive: true });
for (const f of artFiles) await copyFile(join(artDir, f), join(out, "art", f));

// 场地的房间背景：web/room/<场地编号>.webp，是场地插画预先缩小、虚化过的版本（铺在牌桌四周，页面上不再实时模糊）
const roomDir = join(web, "room");
const roomFiles = (await readdir(roomDir).catch(() => [])).filter((f) => f.endsWith(".webp"));
await mkdir(join(out, "room"), { recursive: true });
for (const f of roomFiles) await copyFile(join(roomDir, f), join(out, "room", f));

// 背景音乐：web/audio/<曲名>.m4a（曲名见 web/music.ts）
const audioDir = join(web, "audio");
const audioFiles = (await readdir(audioDir).catch(() => [])).filter((f) => f.endsWith(".m4a"));
await mkdir(join(out, "audio"), { recursive: true });
for (const f of audioFiles) await copyFile(join(audioDir, f), join(out, "audio", f));
console.log(`已输出到 ${out}（${gameVersion} · ${buildId}，内容 ${version}，app.js ${(js.length / 1024).toFixed(1)} KB，立绘 ${artIds.length} 张，音乐 ${audioFiles.length} 首）`);
