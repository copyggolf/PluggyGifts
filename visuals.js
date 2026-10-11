export const paths={atlas:'assets/v2/atlas.avif',promos:'assets/v2/promos.avif',catcher:'assets/v2/catcher.avif',hero:'assets/v2/hero.avif',stage:'assets/v2/stage.avif',pluggy:'assets/pose2.webp'};
export const images={};
export const ready=Promise.all(Object.entries(paths).map(async([k,path])=>{const i=new Image();i.src=path;await i.decode();images[k]=i}));
export const applianceNames=['ทีวี','ตู้เย็น','เครื่องเล่นเกม','มือถือ','เครื่องซักผ้า','เตารีด','เครื่องเสียง','หูฟัง','หม้ออบลมร้อน','ที่ม้วนผม','ที่หนีบผม','พัดลม','แอร์'];
export function sprite(index,{promo=false,classes='',label=''}={}){const n=promo?2:4;const x=index%n,y=Math.floor(index/n);return `<span role="img" aria-label="${label}" data-sprite="${index}" class="sprite ${promo?'promo':''} ${classes}" style="--sx:${x/(n-1)*100}%;--sy:${y/(n-1)*100}%"></span>`}
export function drawSprite(ctx,index,x,y,size,promo=false){const im=images[promo?'promos':'atlas'];if(!im)return;const n=promo?2:4,sw=im.width/n,sh=im.height/n;ctx.drawImage(im,index%n*sw,Math.floor(index/n)*sh,sw,sh,x-size/2,y-size/2,size,size)}
