# วิธีเปลี่ยนภาพปกและฉากเกม

ภาพชุด Festive Wonderland แยกเป็น 6 ไฟล์ใน `assets/missions/`:

| เกม | ภาพปก | ฉากหลัง |
| --- | --- | --- |
| Pluggy Catch | catch-cover.webp | catch-bg.webp |
| Pluggy Buster | buster-cover.webp | buster-bg.webp |
| Pluggy Mystery Shuffle | shuffle-cover.webp | shuffle-bg.webp |

1. เตรียมภาพปกสี่เหลี่ยมจัตุรัส 1024 × 1024 และภาพฉากแนวนอน 1536 × 1024 ในรูปแบบ WebP
2. ภาพปกควรวางหน้าปลั๊กกี้และองค์ประกอบสำคัญไว้กลางภาพ ฉากหลังควรเว้นตรงกลางให้โล่ง ตัวละครและอุปกรณ์ที่เล่นได้เป็นส่วนของเกมอยู่แล้ว
3. เปิด GitHub repository PluggyGifts → assets → missions → Add file → Upload files
4. อัปโหลดภาพใหม่ด้วยชื่อเดียวกับไฟล์ที่ต้องการแทน แล้วกด Commit changes
5. รอการเผยแพร่ GitHub Pages เสร็จ แล้วรีเฟรชหน้าเว็บ หากเครื่องยังแสดงภาพเก่า ให้เพิ่มเลขหลัง `?v=` ในชื่อภาพที่ไฟล์ game-config.js และเพิ่มเลขเวอร์ชัน import game-config.js ใน app.js พร้อมเลข app.js ใน index.html

เปลี่ยนเฉพาะภาพได้โดยไม่ต้องสร้างเกมใหม่ ไม่ต้องแก้ฐานข้อมูล และไม่ต้องใช้ AI หากมีภาพพร้อมแล้ว

ภาพปกและฉากรอบนี้สร้างด้วย built-in ImageGen ตามชุด A ที่เจ้าของเว็บเลือก อ้างอิงรายละเอียดการสร้างใน ART-PROMPTS.md
