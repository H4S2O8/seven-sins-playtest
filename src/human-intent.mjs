import { distance } from "./geometry.mjs";

// An explicit instruction changes the target, not the rescue clock or satisfaction rules.
export function desiredProp(h, props, index) {
  const available = props.filter(
    (p) => p.type === "temptation" && p.active && p.index === index,
  );
  return (
    available.find((p) => p.id === h.preferred) ||
    available.sort((a, b) => distance(h, a) - distance(h, b))[0]
  );
}
export function desiredOpponent(h, opponents, sin) {
  if (sin === "wrath") {
    h.markId ??= opponents
      .slice()
      .sort((a, b) => distance(h, a) - distance(h, b))[0]?.id;
    return opponents.find((e) => e.id === h.markId);
  }
  return (
    opponents.find((e) => e.id === h.targetId) ||
    opponents.slice().sort((a, b) => distance(h, a) - distance(h, b))[0]
  );
}
export function desiredPartner(h, humans, player) {
  const available = humans.filter(
    (e) => e !== h && !["rescued", "recovered"].includes(e.state),
  );
  return available.find((e) => e.id === h.partnerId) || available[0] || player;
}
