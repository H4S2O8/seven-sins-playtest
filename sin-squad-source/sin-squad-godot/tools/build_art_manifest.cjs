// Read-only PNG analysis plus generated metadata. This never rewrites source images.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const {PNG} = require('C:/Users/27654/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/pngjs');
const project = path.resolve(__dirname, '..');
const sources = path.join(project, 'assets/sources');
const catalog = JSON.parse(fs.readFileSync(path.join(project, 'content/characters/characters.json'), 'utf8')).characters;
const execution = fs.readFileSync(path.join(project, '../sin-squad-design/execution-v1/04-98人物演出表.md'), 'utf8');
const views = ['front','back','front_three_quarter','back_three_quarter'];
const sourceIndex = {};
const warnings = [];
function loadImage(relative) {
  const bytes = fs.readFileSync(path.join(sources, relative));
  const png = PNG.sync.read(bytes);
  sourceIndex[relative] = {width:png.width,height:png.height,sha256:crypto.createHash('sha256').update(bytes).digest('hex')};
  return png;
}
function ink(png,x,y) {return png.data[(y * png.width + x) * 4 + 3] >= 64;}
// Search near an expected separator for the sparsest alpha band. Generation can
// shift row heights; a straight 4x4 split is NOT assumed to be a verified crop.
function separator(png,axis,expected,radius,low,high) {
  const end=axis==='x'?png.width:png.height;
  const first=Math.max(1,Math.round(expected-radius)), last=Math.min(end-1,Math.round(expected+radius));
  let best=first,bestCost=Infinity;
  for(let p=first;p<=last;p++) {
    let count=0;
    for(let q=low;q<high;q++) for(let d=-1;d<=1;d++) {
      const x=axis==='x'?p+d:q,y=axis==='y'?p+d:q;
      if(x>=0&&x<png.width&&y>=0&&y<png.height&&ink(png,x,y)) count++;
    }
    const cost=count*1000+Math.abs(p-expected);
    if(cost<bestCost){bestCost=cost;best=p;}
  }
  return best;
}
function bounds(png,cell,id) {
  const [x0,y0,x1,y1]=cell;
  let l=x1,t=y1,r=x0-1,b=y0-1,pixels=0,edge=0;
  for(let y=y0;y<y1;y++) for(let x=x0;x<x1;x++) if(ink(png,x,y)) {
    l=Math.min(l,x);t=Math.min(t,y);r=Math.max(r,x);b=Math.max(b,y);pixels++;
    if(x<=x0+1||x>=x1-2||y<=y0+1||y>=y1-2) edge++;
  }
  if(!pixels) throw new Error('Empty image cell: '+id);
  // The foot is the median of ink in the final 3% of the silhouette, not the
  // centre of its weapon-expanded rectangle. It still needs human review.
  const feet=[];
  for(let y=Math.max(t,b-Math.ceil((b-t)*.03));y<=b;y++) for(let x=l;x<=r;x++) if(ink(png,x,y)) feet.push(x);
  feet.sort((a,b)=>a-b);
  const fx=feet[Math.floor(feet.length/2)];
  l=Math.max(x0,l-2);t=Math.max(y0,t-2);r=Math.min(x1-1,r+2);b=Math.min(y1-1,b+2);
  if(edge) warnings.push({id,kind:'alpha_touches_cell_boundary',pixels:edge});
  return {region_px:[l,t,r-l+1,b-t+1],foot_px:[fx-l,b-t],crop_status:'needs_visual_review',edge_ink_pixels:edge};
}
function artSpec(id) {
  const line=execution.split(/\r?\n/).find(x=>x.startsWith('| '+id+' '));
  if(!line) throw new Error('No visual direction for '+id);
  const cells=line.split('|').slice(1,-1).map(x=>x.trim());
  const attack=cells[2].match(/^[MR][1-5]/)?.[0];
  if(!attack) throw new Error('No attack family '+id);
  return {silhouette:cells[1],attack_family:attack,attack_description:cells[2],talent_visual:cells[3]};
}
const characters={};
for(const folder of fs.readdirSync(path.join(sources,'characters'),{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>x.name)) {
  const relative='characters/'+folder+'/turnaround-v1.png';
  if(!fs.existsSync(path.join(sources,relative))) continue;
  const png=loadImage(relative);
  const ids=folder.split('-');
  const start=catalog.findIndex(x=>x.id===ids[0]);
  const stop=catalog.findIndex(x=>x.id===ids[ids.length-1]);
  if(start<0||stop<start) throw new Error('Invalid character range '+folder);
  const batch=catalog.slice(start,stop+1);
  if(batch.length!==1&&batch.length!==4) throw new Error('Expected one or four characters '+folder);
  const rows=batch.length===1?2:4,cols=batch.length===1?2:4;
  const ys=[0];
  for(let row=1;row<rows;row++) ys.push(separator(png,'y',png.height*row/rows,png.height/rows*.18,0,png.width));
  ys.push(png.height);
  const regions=[];
  for(let row=0;row<rows;row++) {
    const xs=[0];
    for(let col=1;col<cols;col++) xs.push(separator(png,'x',png.width*col/cols,png.width/cols*.17,ys[row],ys[row+1]));
    xs.push(png.width);
    for(let col=0;col<cols;col++) regions.push([xs[col],ys[row],xs[col+1],ys[row+1]]);
  }
  batch.forEach((character,index)=>{
    if(characters[character.id]) throw new Error('Duplicate '+character.id);
    const record={id:character.id,name:character.name,sin:character.sin,source:'res://assets/sources/'+relative,...artSpec(character.id),views:{},animation_status:'not_implemented'};
    views.forEach((view,v)=>{record.views[view]=bounds(png,regions[batch.length===1?v:index*4+v],character.id+':'+view);});
    characters[character.id]=record;
  });
}
if(Object.keys(characters).length!==98) throw new Error('Missing character source identities');
const attachments={};
for(const [prefix,directory] of [['EQ','equipment'],['FX','effects']]) {
  for(const start of [1,17,33]) {
    const relative=directory+'/'+prefix.toLowerCase()+String(start).padStart(2,'0')+'-'+String(start+15).padStart(2,'0')+'-v1.png';
    const png=loadImage(relative);
    for(let i=0;i<16;i++) {
      const id=prefix+String(start+i).padStart(2,'0'),row=Math.floor(i/4),col=i%4;
      const cell=[Math.floor(png.width*col/4),Math.floor(png.height*row/4),Math.floor(png.width*(col+1)/4),Math.floor(png.height*(row+1)/4)];
      attachments[id]={id,source:'res://assets/sources/'+relative,...bounds(png,cell,id)};
    }
  }
}
const tail='equipment/attachment-tail-v1.png';
if(fs.existsSync(path.join(sources,tail))) {
  const png=loadImage(tail);
  ['EQ49','EQ50','FX49','FX50'].forEach((id,i)=>{
    const col=i%2,row=Math.floor(i/2);
    attachments[id]={id,source:'res://assets/sources/'+tail,...bounds(png,[Math.floor(png.width*col/2),Math.floor(png.height*row/2),Math.floor(png.width*(col+1)/2),Math.floor(png.height*(row+1)/2)],id)};
  });
}
const manifest={schema_version:1,purpose:'source-art-addressing-only',not_acceptance:['crop review','articulated animation','talent VFX','formal content'],source_index:sourceIndex,characters,attachments,warnings};
const output=path.join(project,'assets/art-manifest.json');
fs.writeFileSync(output,JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({output,characters:Object.keys(characters).length,views:Object.keys(characters).length*4,attachments:Object.keys(attachments).length,warnings:warnings.length,animation_status:'not_implemented'},null,2));
