import { describe, expect, it } from "vitest";
import { NumericAgent, type NumericStyle } from "../src/numeric/ai.js";
import { NumericTable } from "../src/numeric/table.js";
import { runNumericResolution } from "../src/numeric/content.js";

function betting(seed=91) {
  const t = new NumericTable({seed});
  while (t.phase !== "bet") { const s=t.observe(0).toAct[0] as 0|1; t.apply(s,t.baselineAction(s)!); }
  return t;
}
describe("numeric AI and save",()=>{
  it("fast evaluation preserves settlement and control results",()=>{
    const t=betting();
    t.players[0].slots![0].effectId="LU2";
    t.players[0].slots![0].equipment={id:"E20",tier:"normal"};
    const input={teams:t.players.map(p=>p.slots!) as [NonNullable<typeof t.players[0]['slots']>,NonNullable<typeof t.players[1]['slots']>],arenaId:t.arenaId,ruleId:t.ruleId};
    const full=runNumericResolution(input), fast=runNumericResolution({...input,recordTrace:false});
    expect(fast).toEqual({...full,trace:[]});
  });
  it("only consumes observations and cannot distinguish unseen opponent cards",()=>{
    const t=betting(), s=t.observe(0).toAct[0] as 0|1, before=t.observe(s);
    t.players[1-s].slots![0].effectId="LU2";
    expect(t.observe(s)).toEqual(before);
    const a=new NumericAgent("bluff",4,3), b=new NumericAgent("bluff",4,3);
    expect(a.act(before)).toEqual(b.act(t.observe(s)));
  });
  it("shows different betting policies including pressure and folds",()=>{
    const totals:Record<string,Record<string,number>>={};
    for (const style of ["cautious","aggressive","bluff"] as NumericStyle[]) {
      const actions:Record<string,number>={}; totals[style]=actions;
      for(let seed=1;seed<=24;seed++) {
        const t=betting(seed); t.apply(1,{type:"bet",amount:50});
        const a=new NumericAgent(style,seed,3).act(t.observe(0))!;
        actions[a.type]=(actions[a.type]??0)+1;
      }
    }
    expect(totals.cautious.fold).toBeGreaterThan(0);
    expect((totals.aggressive.raise??0)+(totals.bluff.raise??0)).toBeGreaterThan(0);
    expect(totals.cautious).not.toEqual(totals.aggressive);
  });
  it("uses equipment as soft evidence without revealing exact numbers",()=>{
    const t=betting(), o=t.observe(0); o.opponent.tiers=["低","中","高"];
    o.opponent.equipment=[{id:"E02",tier:"normal"},null,null];
    const hypotheses=new NumericAgent("cautious",14,3).hypotheses(o,120);
    const lows=hypotheses.filter(h=>h[0].number<=4).length;
    expect(lows).toBeGreaterThan(50); expect(lows).toBeLessThan(120);
    expect(new Set(hypotheses.map(h=>h[0].number)).size).toBeGreaterThan(2);
  });
  it("restores hidden pending choices and AI random state exactly",()=>{
    const t=betting(); t.apply(1,{type:"check"});t.apply(0,{type:"check"});
    t.apply(0,{type:"operate",draft:true});t.apply(0,{type:"equip",offerIndex:1,pos:2});
    t.aiAction(1,"aggressive");
    const copy=NumericTable.restore(JSON.parse(JSON.stringify(t.save())));
    expect(copy.observe(0)).toEqual(t.observe(0));expect(copy.observe(1)).toEqual(t.observe(1));
    const a=t.aiAction(1,"aggressive"),b=copy.aiAction(1,"aggressive");expect(b).toEqual(a);
    t.apply(1,a!);copy.apply(1,b!);expect(copy.observe(1)).toEqual(t.observe(1));
  });
  it("rejects corrupted or unsupported saved games",()=>{
    expect(()=>NumericTable.restore({version:999} as never)).toThrow();
    const data=betting().save();data.history.push({seat:0,action:{type:"equip",offerIndex:99,pos:99}});
    expect(()=>NumericTable.restore(data)).toThrow();
  });
  it("plays legal actions through every decision phase",()=>{
    for(let seed=1;seed<=3;seed++) {
      const t=new NumericTable({seed});const agents=[new NumericAgent("aggressive",seed,2),new NumericAgent("bluff",seed+10,2)];
      let n=0;
      while(!t.observe(0).result && n++<200) {const s=t.observe(0).toAct[0] as 0|1;const a=agents[s].act(t.observe(s));expect(a).toBeTruthy();t.apply(s,a!);expect(t.pot+t.players[0].stack+t.players[1].stack).toBe(200);}
      expect(t.observe(0).result).toBeTruthy();
    }
  },15000);
});
