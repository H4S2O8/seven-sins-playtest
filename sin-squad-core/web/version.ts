/**
 * 版本号和构建号，由 scripts/build-web.mjs 打包时写入。
 * VERSION 是 package.json 版本的前两位（“v0.4”），改规则时手动升；BUILD 是“构建日期 · 提交号”（“09-26 · 99c1f99”），
 * 每次部署自动变，反馈问题时能对上是哪一次部署。
 */
declare const __GAME_VERSION__: string;
declare const __BUILD__: string;

export const VERSION = typeof __GAME_VERSION__ === "undefined" ? "v?" : __GAME_VERSION__;
export const BUILD = typeof __BUILD__ === "undefined" ? "" : __BUILD__;
