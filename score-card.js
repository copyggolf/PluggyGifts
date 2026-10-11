import {images,ready} from './visuals.js?v=5';
export async function makeScoreCard({name,game,score,rounds,praise}){
 await ready;await document.fonts.ready;const c=document.createElement('canvas');c.width=1080;c.height=1350;const x=c.getContext('2d');
 const g=x.createLinearGradient(0,0,1080,1350);g.addColorStop(0,'#352060');g.addColorStop(1,'#12091f');x.fillStyle=g;x.fillRect(0,0,1080,1350);
 x.globalAlpha=.23;x.drawImage(images.showroom,0,0,1080,720);x.globalAlpha=1;
 x.strokeStyle='#a47ddd';x.lineWidth=3;x.beginPath();x.roundRect(36,36,1008,1278,40);x.stroke();
 const text=(s,y,size,color='#fff',weight=800)=>{x.textAlign='center';x.fillStyle=color;x.font=`${weight} ${size}px "Noto Sans Thai",sans-serif`;x.fillText(s,540,y,950)};
 text('Power Buy',107,42);text('Power Up Your Life',143,23,'#e2c9ff',500);
 text('POWER OF GIFTS WITH PLUGGY',213,29,'#ffcf85');text(game,264,32);
 const im=images.hammer;x.drawImage(im,350,293,380,380*im.height/im.width);
 text(name,765,51);text(String(score),918,130,'#ffc576',900);text('คะแนนรวม',972,28,'#dec6ee');
 const gap=880/rounds.length;x.font='700 24px "Noto Sans Thai",sans-serif';rounds.forEach((n,i)=>{const cx=100+gap*(i+.5);x.fillStyle='#ffffff0f';x.beginPath();x.roundRect(cx-gap*.43,1010,gap*.86,83,15);x.fill();x.fillStyle='#d6bde7';x.fillText(`${i+1}`,cx,1040);x.fillStyle='#ffd49a';x.fillText(String(n),cx,1075)});
 text(praise,1151,28,'#efd9ff',600);text('ไปช้อปของขวัญเลือกได้หลากหลาย',1208,29,'#ffc576');text('ที่ Power Buy เลย',1252,34,'#ffc576');
 return new Promise((resolve,reject)=>c.toBlob(b=>b?resolve(b):reject(new Error('สร้างภาพไม่สำเร็จ')),'image/png'));
}
export function downloadBlob(blob,name){const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=name;document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),60000)}
