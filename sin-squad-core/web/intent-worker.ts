import { Bot } from "../src/intent/agent.js";
import type { Observation } from "../src/intent/types.js";
const scope = globalThis as unknown as {
  onmessage:
    | ((
        e: MessageEvent<{
          id: number;
          observation: Observation;
          style: "balanced" | "cautious" | "pressure";
        }>,
      ) => void)
    | null;
  postMessage: (data: unknown) => void;
};
scope.onmessage = (e) => {
  try {
    const { id, observation, style } = e.data;
    const bot = new Bot(
      719 + observation.history.length * 31 + observation.round,
      style,
    );
    scope.postMessage({ id, action: bot.decide(observation).action });
  } catch (error) {
    scope.postMessage({ id: e.data.id, error: String(error) });
  }
};
