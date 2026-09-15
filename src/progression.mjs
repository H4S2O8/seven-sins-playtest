export const CODES = {
  gluttony: "G",
  wrath: "W",
  greed: "A",
  pride: "P",
  envy: "E",
  lust: "L",
  sloth: "S",
};
export function initProgress(save) {
  save.learned ??= {};
  save.equipped ??= {};
  save.slots ??= {};
  save.basicRanks ??= {};
  for (const prefix of Object.values(CODES)) {
    save.learned[prefix + "01"] ??= 1;
    save.learned[prefix + "06"] ??= 1;
    save.equipped[prefix] ??= [prefix + "01", prefix + "06"];
    save.slots[prefix] ??= 2;
    save.basicRanks[prefix] ??= [0, 0, 0, 0, 0, 0];
  }
  return save;
}
export function skillPrice(node, rank) {
  return [40, 80, 160, 280, 440][(node.i - 1) % 5] * [1, 1.5, 2.5][rank];
}
export function learn(save, tree, node) {
  const rank = save.learned[node.code] || 0;
  if (rank >= 3) return "已达到三级";
  if (
    !node.parents.every(
      ([i, r]) =>
        (save.learned[tree.id + String(i).padStart(2, "0")] || 0) >= r,
    )
  )
    return "前置技能等级不足";
  const price = skillPrice(node, rank);
  if (save.currency < price) return "材料不足";
  save.currency -= price;
  save.learned[node.code] = rank + 1;
  return null;
}
export function equip(save, prefix, code) {
  const list = save.equipped[prefix];
  if (list.includes(code)) {
    save.equipped[prefix] = list.filter((c) => c !== code);
    return null;
  }
  if (!save.learned[code]) return "尚未学习";
  if (list.length >= save.slots[prefix]) return "技能槽已满，请先卸下一项";
  list.push(code);
  return null;
}
export function passiveRank(save, code) {
  return save.equipped[code[0]]?.includes(code) ? save.learned[code] || 0 : 0;
}
export function buySlot(save, prefix) {
  const count = save.slots[prefix];
  if (count >= 5) return "已达到五个技能槽";
  const cost = [300, 800, 1800][count - 2];
  if (save.currency < cost) return "材料不足";
  save.currency -= cost;
  save.slots[prefix]++;
  return null;
}
export function buyBasic(save, prefix, stage) {
  const rank = save.basicRanks[prefix][stage];
  if (rank >= 2) return "已达到三级";
  const cost = [30, 50, 80, 120, 180, 260][stage] * (rank + 1);
  if (save.currency < cost) return "材料不足";
  save.currency -= cost;
  save.basicRanks[prefix][stage]++;
  return null;
}
