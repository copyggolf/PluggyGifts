// New missions register here and in the renderer map. Scores are native points, without a display cap.
export const games=[
{id:'catch',roundCount:1,seconds:25,cover:'assets/update/catch-cover.webp',background:'assets/missions/catch-bg.webp?v=10',name:'Pluggy Catch',thai:'ของขวัญชิ้นนี้ปลั๊กกี้ขอนะ',desc:'เลือก 3 ระดับความเร็ว รับสินค้า หลบสายไฟ แล้วคว้าโบนัสแอป!',time:'25 วินาที · 3 โหมดความยาก',steps:['เลือกโหมดที่ชอบ แล้วลากนิ้วหรือเมาส์รับสินค้า','หลบ Cable Monster และรับสินค้าให้ทัน','รับโลโก้ Power Buy APP เป็นโบนัส 1 ครั้ง'],rules:'ลากนิ้ว / เมาส์ / ปุ่มลูกศรซ้ายขวา<br>โหมดที่เร็วขึ้น ได้คะแนนต่อชิ้นมากขึ้น'},
{id:'buster',roundCount:1,seconds:25,cover:'assets/update/buster-cover.webp',background:'assets/missions/buster-bg.webp?v=10',name:'Pluggy Buster',thai:'ทุบสินค้าพาไปช้อป',desc:'จำให้แม่น! ทุบสินค้าที่ Power Buy มีขาย หลบของที่ไม่มีขาย',time:'25 วินาที · เล่นรอบเดียว',steps:['ทุบสินค้าที่มีขาย: แอร์ ตู้เย็น ทีวี มือถือ หูฟัง เตารีด และเกม +100','ห้ามทุบ: เสื้อผ้า หนังสือ ก๋วยเตี๋ยว และต้นไม้ ถ้าทุบเสีย −100','แตะสินค้าที่เด้งขึ้นมาให้ทัน · กดเลข 1–9 ได้บนคอมพิวเตอร์'],rules:'สินค้า Power Buy: ทุบ +100<br>ของที่ไม่มีขาย: ห้ามทุบ หากทุบ −100<br>แตะ / คลิก / กดเลข 1–9'},
{id:'shuffle',roundCount:2,cover:'assets/update/shuffle-cover.webp',background:'assets/missions/shuffle-bg.webp?v=10',name:'Pluggy Mystery',thai:'Shuffle · ของขวัญอยู่ไหนน้าาา',desc:'จำกล่องของขวัญ แล้วตามการสลับบนโต๊ะให้ทัน',time:'ทายเพียง 2 ครั้ง · 3 และ 4 กล่อง',steps:['จำกล่องที่มีสินค้า เปิดให้ดูประมาณ 3 วินาที','ตามกล่องบนโต๊ะ แล้วรอจนกล่องหยุด','เลือก 1 กล่อง · ถูก +500 · ผิด −200 · เล่น 2 ครั้ง'],rules:'ดูของขวัญ แล้วตามการสลับกล่อง<br>รอ “เลือกกล่อง” ก่อนแตะเลือก 1 กล่อง<br>ทายถูก +500 · ทายผิด −200<br>รวม 2 ครั้ง · สะสมคะแนนตามที่ทายได้'}];
export const catchModes={
 easy:{name:'ง่าย',note:'ค่อย ๆ รับ ฝึกให้คล่อง',flight:3.1,interval:.9,gift:30,miss:5,cable:50,bonus:100},
 normal:{name:'ปกติ',note:'เร็วขึ้น สนุกกำลังดี',flight:2.3,interval:.65,gift:50,miss:10,cable:80,bonus:200},
 hard:{name:'ท้าทาย',note:'ของลงไว ลุ้นคะแนนสูง',flight:1.65,interval:.44,gift:80,miss:20,cable:120,bonus:300}
};
export const gameById=id=>games.find(g=>g.id===id);
