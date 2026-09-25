#!/usr/bin/env node
"use strict";

// Imports the exact EQ/FX source fields; ability prose is never executable.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const projectRoot = path.resolve(__dirname, "..");
const sourcePath = path.resolve(projectRoot, "..", "sin-squad-design", "02-装备与槽位.md");
const outputDir = path.join(projectRoot, "content", "attachments");
const EXPECTED_SOURCE_HASH = "5E7A8EC39406C64013C15F867DBE61DA4639BE7CBA3611E0C92AC144703E2DBD";
const source = fs.readFileSync(sourcePath, "utf8").replace(/^\uFEFF/, "");
const sourceHash = crypto.createHash("sha256").update(source, "utf8").digest("hex").toUpperCase();
if (sourceHash !== EXPECTED_SOURCE_HASH) throw new Error(`装备/槽效来源哈希不匹配：${sourceHash}`);

const initialModifiers = {
  EQ01: [{ stat: "A_flat", amount: 3 }],
  EQ02: [{ stat: "H_max_flat", amount: 18, also_current_hp: true }],
  EQ03: [{ stat: "T_ticks_flat", amount: -2 }],
  EQ04: [{ stat: "R_flat", amount: 3 }],
  EQ10: [{ stat: "T_ticks_flat", amount: 2 }],
  EQ12: [
    { stat: "flying", value: true },
    { stat: "H_max_flat", amount: -12, minimum: 1, also_current_hp: true, current_hp_minimum: 1 },
  ],
  EQ13: [
    { stat: "reach", value: "ranged" },
    { stat: "A_flat", amount: -3, minimum: 1 },
  ],
  EQ24: [{ stat: "T_ticks_flat", amount: 2 }],
  EQ26: [
    { stat: "attack_damage_bp", amount: 4500 },
    { stat: "T_ticks_flat", amount: 6 },
  ],
  EQ39: [{ stat: "A_flat", amount: -1, minimum: 1 }],
};

const lines = source.replace(/\r\n/g, "\n").split("\n");
const heading = /^### (EQ|FX)(\d{2})｜(.+)$/;
const cards = [];
for (let i = 0; i < lines.length; i++) {
  const match = lines[i].match(heading);
  if (!match) continue;
  const id = `${match[1]}${match[2]}`;
  const fieldLines = lines.slice(i + 1, i + 4);
  const fields = {};
  for (const [index, key] of [[0, "effect"], [1, "adaptation"], [2, "tradeoff"]]) {
    const prefix = ["效果：", "适配：", "取舍："][index];
    if (!fieldLines[index]?.startsWith(prefix)) throw new Error(`${id} 源字段顺序/缺项错误`);
    fields[key] = fieldLines[index].slice(prefix.length);
  }
  const sourceText = lines.slice(i, i + 4).join("\n");
  cards.push({
    id,
    name: match[3],
    category: match[1],
    legal_slot_type: match[1] === "EQ" ? "equipment" : "effect",
    source: "02-装备与槽位.md",
    source_hash: sourceHash,
    source_text: sourceText,
    ...fields,
    initial_modifiers: (initialModifiers[id] || []).map((item) => ({ ...item, phase: "pre_battle_setup" })),
    ...(id === "FX43" ? { trigger_scope: "event_target" } : {}),
    logic_handler: `attachment_${id}`,
    implementation_status: "not_implemented",
    positive_test: "required_not_implemented",
    negative_test: "required_not_implemented",
    lifecycle_test: "required_not_implemented",
  });
}

const expected = new Set([
  ...Array.from({ length: 50 }, (_, i) => `EQ${String(i + 1).padStart(2, "0")}`),
  ...Array.from({ length: 50 }, (_, i) => `FX${String(i + 1).padStart(2, "0")}`),
]);
const seen = new Set();
for (const card of cards) {
  if (seen.has(card.id)) throw new Error(`重复附件 ID：${card.id}`);
  seen.add(card.id);
  if (!card.name || !card.effect || !card.adaptation || !card.tradeoff) throw new Error(`${card.id} 有空的源字段`);
}
if (cards.length !== 100 || seen.size !== 100 || [...expected].some((id) => !seen.has(id))) {
  throw new Error(`装备/槽效 ID 覆盖错误：count=${cards.length}`);
}

const document = {
  schema_version: 1,
  source: { file: "sin-squad-design/02-装备与槽位.md", sha256: sourceHash },
  count: cards.length,
  counts: { equipment: 50, slot_effect: 50 },
  formal_pool_enabled: false,
  note: "source_text 与 effect/adaptation/tradeoff 原文忠实导入；handler 不得从中文文本推断；setup modifiers 在 battle_start 前应用，不生成战斗触发事件。",
  attachments: cards,
};
const requirements = {
  schema_version: 1,
  source: document.source,
  count: cards.length,
  formal_pool_blocked: true,
  bindings: cards.map((card) => ({
    content_id: card.id,
    logic_handler: card.logic_handler,
    binding_kind: card.legal_slot_type,
    ...(card.trigger_scope ? { trigger_scope: card.trigger_scope } : {}),
    required_source_key: `unit_instance_key:${card.id}`,
    effect: card.effect,
    positive_case: card.positive_test,
    negative_case: card.negative_test,
    expiry_or_departure_case: card.lifecycle_test,
    implementation_status: card.implementation_status,
  })),
};

fs.mkdirSync(outputDir, { recursive: true });
fs.writeFileSync(path.join(outputDir, "attachments.json"), `${JSON.stringify(document, null, 2)}\n`, "utf8");
fs.writeFileSync(path.join(outputDir, "handler-requirements.json"), `${JSON.stringify(requirements, null, 2)}\n`, "utf8");
console.log(`ATTACHMENTS_IMPORTED count=${cards.length} EQ=50 FX=50 unique=${seen.size} sha256=${sourceHash} formal_pool=blocked`);
