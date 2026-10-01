// Tiny arithmetic audit for one live defender. This does not simulate a full battle.
// 100 construction points: one defender's HP, one defense number, a 20-point
// independent attack, and one HP for each of the other four minions.
const budget=100, offense=20, otherHp=4;
const cases=[];
for(const D of [10,20,30]){
 for(const multiplier of [1,2,3,4]){
  const incoming=D*multiplier;
  const healNumber=Math.min(25,D);
  const healHp=budget-offense-otherHp-healNumber;
  const afterHeal=Math.max(0,healHp-incoming+healNumber);
  const reduction=20; // existing provisional curve: 20 points = 50%
  const reductionHp=budget-offense-otherHp-reduction;
  const afterReduction=Math.max(0,reductionHp-Math.ceil(incoming/2));
  cases.push({D,multiplier,incoming,heal:{hp:healHp,number:healNumber,remaining:afterHeal,canRespondAtRound2:healNumber+5<=30},
    reduction:{hp:reductionHp,number:reduction,remaining:afterReduction,canRespondAtRound2:reduction+5<=30}});
 }
}
console.table(cases.map(c=>({D:c.D,m:c.multiplier,healRemaining:c.heal.remaining,reduceRemaining:c.reduction.remaining})));
if(!cases.filter(c=>c.D<=30&&c.multiplier<=2).every(c=>c.heal.remaining>0&&c.reduction.remaining>0))throw new Error('早期普通/双倍范围伤害存在开局攻守预算反例');
