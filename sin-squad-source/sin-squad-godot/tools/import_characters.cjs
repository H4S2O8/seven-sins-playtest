#!/usr/bin/env node
"use strict";

// Imports the 98 character cards from the design source without interpreting
// ability prose as executable logic.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const projectRoot = path.resolve(__dirname, "..");
const sourcePath = path.resolve(projectRoot, "..", "sin-squad-design", "01-人物.md");
const outputDir = path.join(projectRoot, "content", "characters");
const sins = {
  WR: "愤怒", GR: "贪婪", GL: "暴食", EN: "嫉妒", SL: "怠惰", LU: "色欲", PR: "傲慢",
};
const expectedHash = "1CE508E93AE694D80DD55CC0F113AA8A6B82E2DBBD3AF81A2622236843704BA5";
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\uFEFF/, "");
const sourceHash = crypto.createHash("sha256").update(source, "utf8").digest("hex").toUpperCase();
if (sourceHash !== expectedHash) throw new Error(`人物设计源哈希不匹配：${sourceHash}`);

const lines = source.replace(/\r\n/g, "\n").split("\n");
const heading = /^### (WR|GR|GL|EN|SL|LU|PR)(\d{2})｜(.+)$/;
const panel = /^面板：H(\d+) \/ A(\d+) \/ T(\d+(?:\.\d+)?)秒 \/ R(\d+) \/ (近|远) \/ (轻甲|中甲|重甲)。$/;
const cards = [];
for (let i = 0; i < lines.length; i++) {
  const match = lines[i].match(heading);
  if (!match) continue;
  const id = `${match[1]}${match[2]}`;
  const panelLine = lines[i + 1] || "";
  const panelMatch = panelLine.match(panel);
  const abilityLine = lines[i + 2] || "";
  if (!panelMatch || !abilityLine.startsWith("能力：")) {
    throw new Error(`${id} 面板或能力字段无法准确解析（源行 ${i + 1}）`);
  }
  const rawTicks = Number(panelMatch[3]) * 10;
  if (!Number.isInteger(rawTicks)) throw new Error(`${id} T无法精确换算为0.1秒ticks`);
  cards.push({
    id,
    name: match[3],
    sin: sins[match[1]],
    H: Number(panelMatch[1]),
    A: Number(panelMatch[2]),
    T_ticks: rawTicks,
    R: Number(panelMatch[4]),
    reach: panelMatch[5] === "近" ? "melee" : "ranged",
    armor_kind: ({ "轻甲": "light", "中甲": "medium", "重甲": "heavy" })[panelMatch[6]],
    ability_text: abilityLine.slice("能力：".length),
    source_hash: sourceHash,
    source_text: lines.slice(i, i + 5).join("\n"),
    logic_handler: `character_${id}`,
    implementation_status: "not_implemented",
    positive_test: false,
    negative_test: false,
    expiry_test: false,
  });
}

const expectedIds = new Set(Object.keys(sins).flatMap((prefix) =>
  Array.from({ length: 14 }, (_, i) => `${prefix}${String(i + 1).padStart(2, "0")}`)));
const seen = new Set();
for (const card of cards) {
  if (seen.has(card.id)) throw new Error(`重复人物ID：${card.id}`);
  seen.add(card.id);
}
if (cards.length !== 98 || seen.size !== 98 || [...expectedIds].some((id) => !seen.has(id))) {
  throw new Error(`人物数量/ID集合校验失败：count=${cards.length}`);
}
for (const prefix of Object.keys(sins)) {
  if (cards.filter((card) => card.id.startsWith(prefix)).length !== 14) {
    throw new Error(`${prefix}人物数不是14`);
  }
}

const document = {
  schema_version: 1,
  source: { file: "sin-squad-design/01-人物.md", sha256: sourceHash },
  count: cards.length,
  handlers_ready_for_formal_pool: false,
  characters: cards,
};
const requirements = {
  schema_version: 1,
  source: { file: "sin-squad-design/01-人物.md", sha256: sourceHash },
  count: cards.length,
  formal_pool_blocked: true,
  note: "每个ID必须由自己的logic_handler绑定；能力原文仅供卡片展示，不允许运行时文本推断。每项正例、反例、到期边界须接入真实BattleEngine后通过。",
  bindings: cards.map((card) => ({
    content_id: card.id,
    logic_handler: card.logic_handler,
    required_binding_kind: "talent",
    required_owner_key: "unit_instance_key",
    required_source_key: `unit_instance_key:${card.id}`,
    ability_text: card.ability_text,
    positive_case: "required_not_implemented",
    negative_case: "required_not_implemented",
    expiry_or_departure_case: "required_not_implemented",
    implementation_status: "not_implemented",
  })),
};

fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, "characters.json"), `${JSON.stringify(document, null, 2)}\n`, "utf8");
fs.writeFileSync(path.join(outputDir, "handler-requirements.json"), `${JSON.stringify(requirements, null, 2)}\n`, "utf8");
console.log(`CHARACTERS_IMPORTED count=${cards.length} sha256=${sourceHash} unique_handlers=${new Set(cards.map((c) => c.logic_handler)).size} formal_pool=blocked`);
