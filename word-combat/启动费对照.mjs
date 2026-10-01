import assert from 'node:assert/strict';
const rows=[3,5,8].map(fee=>({fee,
  firstRoundMaxFilled:10-fee,
  secondRoundMaxFilledIfSaved:30-fee,
  secondRoundMaxFilledAfterOneZeroNumberAction:30-2*fee,
  canCastTwentyPointSkillInSecondRoundAfterFirstRoundResponse:30-2*fee>=20,
  canInstallTwentySecondWatcherInSecondRoundAfterFirstRoundResponse:30-2*fee>=20}));
assert.deepEqual(rows.map(x=>x.secondRoundMaxFilledAfterOneZeroNumberAction),[24,20,14]);
console.table(rows);
