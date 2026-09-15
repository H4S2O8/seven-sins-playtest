// Satisfaction is an event or an achieved condition, never simply 'an attack hit'.
// These predicates are shared by player and residents; the consequence differs.
export function fulfilled(sin, event) {
  switch (sin) {
    case "gluttony":
      return event.kind === "consume" && event.amount > 0;
    case "wrath":
      return (
        event.kind === "revenge" &&
        event.target === event.mark &&
        event.damage > 0
      );
    case "greed":
      return event.kind === "acquire" && event.amount > 0;
    case "pride":
      return event.kind === "displace" && event.distance >= 25;
    case "envy":
      return event.kind === "copy" && event.newAbility === true;
    case "lust":
      return (
        event.kind === "bond" && event.duration >= 2 && event.distance <= 90
      );
    case "sloth":
      return event.kind === "rest" && event.duration >= 3;
    default:
      return false;
  }
}
export function frustrated(sin, event) {
  switch (sin) {
    case "gluttony":
      return event.kind === "meal-denied";
    case "wrath":
      return event.kind === "mark-escaped";
    case "greed":
      return event.kind === "possession-lost";
    case "pride":
      return event.kind === "displace" && event.distance < 25;
    case "envy":
      return event.kind === "copy-denied";
    case "lust":
      return event.kind === "bond-broken";
    case "sloth":
      return event.kind === "rest-interrupted";
    default:
      return false;
  }
}
export function dominantDesire(meters) {
  return Object.keys(meters).reduce(
    (best, id) => (meters[id] > (meters[best] || 0) ? id : best),
    "gluttony",
  );
}
