// Runtime sprite matte. Never changes the generated source files.
export function removeMagentaPixels(data){
 for(let i=0;i<data.length;i+=4){const r=data[i],g=data[i+1],b=data[i+2],excess=Math.min(r,b)-g;
  if(excess<=25||r<b*.65||b<r*.65)continue;
  if(r>140&&b>140&&g<120&&excess>75){data[i+3]=0;continue;}
  // Unmix a magenta matte from antialiased edge pixels instead of leaving a pink halo.
  const alpha=Math.max(.01,1-excess/255),matte=255*(1-alpha);
  data[i]=Math.max(0,(r-matte)/alpha);data[i+1]=Math.min(255,g/alpha);data[i+2]=Math.max(0,(b-matte)/alpha);data[i+3]*=alpha;
 }
 return data;
}
export function keyedAtlas(image){const c=document.createElement('canvas');c.width=image.width;c.height=image.height;const g=c.getContext('2d',{willReadFrequently:true});g.drawImage(image,0,0);const pixels=g.getImageData(0,0,c.width,c.height);removeMagentaPixels(pixels.data);g.putImageData(pixels,0,0);return c;}
