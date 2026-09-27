import type { NumericTrace, NumericStats } from "./content.js";
export type NumericAction =
  | {type:"keep";index:number}|{type:"reroll"}|{type:"place";effects:[number,number,number];numbers:[number,number,number]}
  | {type:"check"}|{type:"bet";amount:number}|{type:"call"}|{type:"raise";to:number}|{type:"allIn"}|{type:"fold"}
  | {type:"operate";draft:boolean}|{type:"equip";offerIndex:number;pos:number}|{type:"vote";activate:boolean}|{type:"bid";amount:number}|{type:"nextHand"};
export interface NumericObservation {
 seat:0|1; publicStats:[NumericStats,NumericStats];
 phase:string;handNo:number;round:number;dealer:number;stacks:[number,number];pot:number;toAct:number[];
 arenaId:string|null;ruleId:string|null;effects:Array<{id:string;status:string}>;opFee:number;canEquip:boolean;bidCap:number;
 me:{numbers:number[];current:string[];kept:string[];rerolled:boolean;locked?:string[];slots:Array<{effectId:string;number:number}>|null;equipment:Array<{id:string;tier:string}|null>;offers:string[]|null};
 opponent:{tiers:string[];placed:boolean;equipment:Array<{id:string;tier:string}|null>};
 betting:{toCall:number;minRaiseTo:number;target:number;roundBet:[number,number]};
 result?:{winner:number|null;pot?:number;payouts?:[number,number];teams?:Array<Array<{effectId:string;number:number;equipmentId?:string|null}>>;powers?:[number[],number[]];lineWinners?:Array<number|null>;trace?:Array<string|NumericTrace>;lines?:string[]}|null;
}
