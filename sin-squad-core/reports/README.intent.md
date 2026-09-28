# Intent experiment reports

These JSON summaries are historical evidence, not measurements of the current web game.

- `intent-1000*` and `intent-model-20.json`: v1 experiment (the model file records actual completion status, not necessarily twenty completed games).
- `intent-v2-*`: v2 experiment.
- `intent-v3-*`: v3 stacking-fields experiment, including 200 state-machine hands and five model hands.
- Current game: `intent-v4-single-field`, described in `../docs/intent-v4-game.md` and `../docs/intent-v4-browser-check.md`. No new bulk balance run is claimed.

Large raw decision/hand JSONL files and progress logs remain local, as do private model sessions. Historical audit scripts refuse to replay a different ruleset. Current evaluation/model scripts write separate `intent-v4-*` files so they cannot overwrite v3 evidence.
