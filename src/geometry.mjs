export function distance(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}
export function segmentDistance(p, a, b) {
  const x = b.x - a.x,
    y = b.y - a.y,
    t = Math.max(
      0,
      Math.min(1, ((p.x - a.x) * x + (p.y - a.y) * y) / (x * x + y * y || 1)),
    );
  return Math.hypot(p.x - a.x - x * t, p.y - a.y - y * t);
}
// Swept movement prevents dashes from tunnelling through physical cover.
export function moveBody(body, target, amount, cover, radius = 18) {
  const d = distance(body, target);
  if (!d) return 0;
  const before = { x: body.x, y: body.y },
    n = Math.ceil(Math.min(d, amount) / 8),
    step = Math.min(d, amount) / Math.max(1, n),
    dx = ((target.x - body.x) / d) * step,
    dy = ((target.y - body.y) / d) * step;
  const free = (x, y) =>
    x >= 165 &&
    x <= 1435 &&
    y >= 430 &&
    y <= 785 &&
    !cover.some((p) => distance({ x, y }, p) < (p.radius || 38) + radius);
  for (let i = 0; i < n; i++) {
    if (free(body.x + dx, body.y + dy)) {
      body.x += dx;
      body.y += dy;
    } else {
      if (free(body.x + dx, body.y)) body.x += dx;
      if (free(body.x, body.y + dy)) body.y += dy;
    }
  }
  return distance(before, body);
}
export function visible(a, b, cover) {
  return !cover.some((p) => segmentDistance(p, a, b) < (p.radius || 38));
}
export function depenetrate(body, cover, radius = 20) {
  const free = (p) =>
    p.x >= 165 &&
    p.x <= 1435 &&
    p.y >= 430 &&
    p.y <= 785 &&
    !cover.some((o) => distance(p, o) < (o.radius || 38) + radius + 2);
  if (free(body)) return true;
  const origin = { x: body.x, y: body.y };
  for (let r = 8; r < 400; r += 8)
    for (let i = 0; i < 32; i++) {
      const a = (i * Math.PI) / 16,
        p = { x: origin.x + Math.cos(a) * r, y: origin.y + Math.sin(a) * r };
      if (free(p)) {
        body.x = p.x;
        body.y = p.y;
        return true;
      }
    }
  return false;
}
export function waypoint(start, goal, cover) {
  const blockingGoal = cover.find(
    (p) => distance(goal, p) < (p.radius || 38) + 21,
  );
  if (blockingGoal) {
    const d = distance(start, blockingGoal) || 1;
    goal = {
      x:
        blockingGoal.x +
        ((start.x - blockingGoal.x) / d) * ((blockingGoal.radius || 38) + 24),
      y:
        blockingGoal.y +
        ((start.y - blockingGoal.y) / d) * ((blockingGoal.radius || 38) + 24),
    };
  }
  const obstacles = cover.map((p) => ({ ...p, radius: (p.radius || 38) + 20 }));
  const enclosing = obstacles.find((p) => distance(start, p) < p.radius + 0.5);
  if (enclosing) {
    const d = distance(start, enclosing) || 1;
    return {
      x: Math.max(
        165,
        Math.min(
          1435,
          enclosing.x + ((start.x - enclosing.x) / d) * (enclosing.radius + 18),
        ),
      ),
      y: Math.max(
        430,
        Math.min(
          785,
          enclosing.y + ((start.y - enclosing.y) / d) * (enclosing.radius + 18),
        ),
      ),
    };
  }
  if (visible(start, goal, obstacles)) return goal;
  const nodes = [start, goal];
  for (const p of obstacles)
    for (let i = 0; i < 8; i++) {
      const a = (i * Math.PI) / 4,
        n = {
          x: p.x + Math.cos(a) * (p.radius + 16),
          y: p.y + Math.sin(a) * (p.radius + 16),
        };
      if (
        n.x > 165 &&
        n.x < 1435 &&
        n.y > 430 &&
        n.y < 785 &&
        !obstacles.some((o) => distance(n, o) < o.radius)
      )
        nodes.push(n);
    }
  const costs = nodes.map(() => Infinity),
    prev = [],
    done = new Set();
  costs[0] = 0;
  for (let step = 0; step < nodes.length; step++) {
    let i = -1;
    for (let j = 0; j < nodes.length; j++)
      if (!done.has(j) && (i < 0 || costs[j] < costs[i])) i = j;
    if (i < 0 || costs[i] === Infinity) break;
    if (i === 1) {
      let k = 1;
      while (prev[k] !== 0 && prev[k] !== undefined) k = prev[k];
      return nodes[k];
    }
    done.add(i);
    for (let j = 0; j < nodes.length; j++) {
      if (done.has(j) || !visible(nodes[i], nodes[j], obstacles)) continue;
      const next = costs[i] + distance(nodes[i], nodes[j]);
      if (next < costs[j]) {
        costs[j] = next;
        prev[j] = i;
      }
    }
  }
  return start;
}
