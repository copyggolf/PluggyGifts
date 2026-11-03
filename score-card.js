import {images,ready} from './visuals.js?v=27';
export async function makeScoreCard({name,game,score,rounds,praise}){
 await ready;await document.fonts.ready;const c=document.createElement('canvas');c.width=1080;c.height=1350;const x=c.getContext('2d');
 const g=x.createLinearGradient(0,0,1080,1350);g.addColorStop(0,'#352060');g.addColorStop(1,'#12091f');x.fillStyle=g;x.fillRect(0,0,1080,1350);
 x.globalAlpha=.23;x.drawImage(images.showroom,0,0,1080,720);x.globalAlpha=1;
 x.strokeStyle='#a47ddd';x.lineWidth=3;x.beginPath();x.roundRect(36,36,1008,1278,40);x.stroke();
 const text=(s,y,size,color='#fff',weight=800)=>{x.textAlign='center';x.fillStyle=color;x.font=`${weight} ${size}px "Noto Sans Thai",sans-serif`;x.fillText(s,540,y,950)};
 text('Power Buy',107,42);text('Power Up Your Life',143,23,'#e2c9ff',500);
 text('POWER OF GIFTS WITH PLUGGY',213,29,'#ffcf85');text(game,264,32);
 const im=images.celebrate;x.drawImage(im,345,293,390,390*im.height/im.width);
 text(name,765,51);text(String(score),918,130,'#ffc576',900);text('คะแนนที่ทำได้',972,28,'#dec6ee');
 const gap=880/rounds.length;x.font='700 24px "Noto Sans Thai",sans-serif';rounds.forEach((n,i)=>{const cx=100+gap*(i+.5);x.fillStyle='#ffffff0f';x.beginPath();x.roundRect(cx-gap*.43,1010,gap*.86,83,15);x.fill();x.fillStyle='#d6bde7';x.fillText(`${i+1}`,cx,1040);x.fillStyle='#ffd49a';x.fillText(String(n),cx,1075)});
 text(praise,1151,28,'#efd9ff',600);text('ไปช้อปของขวัญเลือกได้หลากหลาย',1208,29,'#ffc576');text('ที่ Power Buy เลย',1252,34,'#ffc576');
 return new Promise((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(new Error('สร้างภาพไม่สำเร็จ')),'image/png'));
}
export function downloadBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000)}

function wrapText(ctx,text,width){const lines=[];for(const para of String(text||'').split('\n')){let line='';for(const ch of Array.from(para)){if(line&&ctx.measureText(line+ch).width>width){lines.push(line);line=ch}else line+=ch}lines.push(line)}return lines}
const canvasBlob=c=>new Promise((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(Error('สร้างภาพไม่สำเร็จ')),'image/png'));
export async function makeCouponCard(coupon){
 let art=null;if(coupon.image){art=new Image();art.src=coupon.image;await art.decode()}
 const c=document.createElement('canvas'),x=c.getContext('2d');c.width=1080;await document.fonts.ready;
 x.font='600 28px "Noto Sans Thai",sans-serif';const title=wrapText(x,coupon.title||'ของขวัญพิเศษจาก Power Buy',960);x.font='400 25px "Noto Sans Thai",sans-serif';const terms=wrapText(x,coupon.terms||'',960);x.font='900 58px "Noto Sans Thai",sans-serif';const codes=coupon.code?wrapText(x,coupon.code,930):[];
 const artHeight=art?972:0,titleHeight=title.length*42,codeHeight=codes.length?codes.length*76+85:0,termsHeight=coupon.terms?terms.length*36+28:0;
 c.height=210+titleHeight+artHeight+codeHeight+termsHeight+(coupon.ends_at?75:20)+110;
 const g=x.createLinearGradient(0,0,1080,c.height);g.addColorStop(0,'#3b2059');g.addColorStop(1,'#160d27');x.fillStyle=g;x.fillRect(0,0,c.width,c.height);x.strokeStyle='#c7a0e7';x.lineWidth=2;x.beginPath();x.roundRect(24,24,1032,c.height-48,28);x.stroke();
 let y=92;x.textAlign='center';x.fillStyle='#ffce88';x.font='900 40px "Noto Sans Thai",sans-serif';x.fillText('POWER BUY · A GIFT FOR YOU',540,y,960);y+=65;x.fillStyle='#fff';x.font='700 32px "Noto Sans Thai",sans-serif';for(const line of title){x.fillText(line,540,y,960);y+=42}y+=24;
 if(art){x.fillStyle='#fff';x.fillRect(54,y,972,972);x.drawImage(art,54,y,972,972);y+=1002}
 if(codes.length){x.fillStyle='#e1c9f1';x.font='500 25px "Noto Sans Thai",sans-serif';x.fillText('โค้ดส่วนลด',540,y+18);y+=75;x.fillStyle='#ffd08b';x.font='900 58px "Noto Sans Thai",sans-serif';for(const line of codes){x.fillText(line,540,y,930);y+=76}y+=10}
 x.fillStyle='#efddf8';x.textAlign='left';x.font='400 25px "Noto Sans Thai",sans-serif';if(coupon.terms){for(const line of terms){x.fillText(line,60,y,960);y+=36}y+=25}
 x.textAlign='center';if(coupon.ends_at){x.fillStyle='#ffd08b';x.font='600 25px "Noto Sans Thai",sans-serif';x.fillText('ใช้ได้ถึง '+new Date(coupon.ends_at).toLocaleString('th-TH',{timeZone:'Asia/Bangkok'})+' น.',540,y+25,960);y+=75}
 x.fillStyle='#dbc3ed';x.font='500 26px "Noto Sans Thai",sans-serif';x.fillText('ใช้สิทธิ์ตามเงื่อนไขที่ Power Buy กำหนด',540,c.height-80,960);x.fillStyle='#ffce88';x.fillText('www.powerbuy.co.th',540,c.height-44,960);return canvasBlob(c);
}
async function decodeResultBlob(blob){if(typeof createImageBitmap==='function')return createImageBitmap(blob);const url=URL.createObjectURL(blob),im=new Image();im.src=url;try{await im.decode();im.close=()=>URL.revokeObjectURL(url);return im}catch(e){URL.revokeObjectURL(url);throw e}}
export async function combineResultCards(scoreBlob,couponBlob){const [a,b]=await Promise.all([decodeResultBlob(scoreBlob),decodeResultBlob(couponBlob)]);try{const c=document.createElement('canvas');c.width=1080;c.height=Math.round(a.height*1080/a.width+b.height*1080/b.width+24);const x=c.getContext('2d');x.fillStyle='#160d27';x.fillRect(0,0,c.width,c.height);const h=Math.round(a.height*1080/a.width);x.drawImage(a,0,0,1080,h);x.drawImage(b,0,h+24,1080,c.height-h-24);return canvasBlob(c)}finally{a.close();b.close()}}
