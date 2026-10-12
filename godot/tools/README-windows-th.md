โต๊ะเทียน (Candlelight Table) แอปรุ่นใหม่ — สำหรับ Windows
=============================================================

ไฟล์นี้เป็นรุ่นทดลองที่สร้างอัตโนมัติจาก GitHub (release build-N) ยังไม่ใช่เกมเต็ม

วิธีเริ่ม
--------
1. แตกไฟล์ zip ออกมาไว้ในโฟลเดอร์ใดก็ได้ (เช่นบน Desktop) — อย่าเปิดจากในไฟล์ zip โดยตรง
2. ดับเบิลคลิก CandlelightTable.exe
3. ถ้า Windows ขึ้นหน้าจอสีน้ำเงิน "Windows protected your PC" ให้กด More info แล้วกด Run anyway
   (แอปยังไม่ได้ซื้อใบรับรองดิจิทัล Windows จึงเตือนทุกไฟล์ใหม่ที่ไม่มีใบรับรอง ไม่ใช่ไวรัส)

ถ้าหน้าต่างดำ หรือเปิดไม่ขึ้น
----------------------------
- อัปเดตไดรเวอร์การ์ดจอก่อน (NVIDIA, AMD หรือ Intel) แล้วเปิดใหม่
- ให้แอปวาดผ่าน DirectX แทน OpenGL:
  คลิกขวาที่ CandlelightTable.exe → Create shortcut → คลิกขวาที่ shortcut นั้น → Properties
  แล้วพิมพ์ต่อท้ายช่อง Target (เว้นวรรคหนึ่งทีก่อน) ว่า
      --rendering-driver opengl3_angle
  กด OK แล้วเปิดจาก shortcut นั้น
- ยังไม่ได้อีก: เปิด Command Prompt (cmd) ในโฟลเดอร์นี้ แล้วพิมพ์
      CandlelightTable.exe --rendering-driver opengl3_angle --resolution 1280x720 --windowed
- บันทึกการทำงาน (log) อยู่ที่  %APPDATA%\Godot\app_userdata\Candlelight Table\logs\
  ส่งไฟล์ล่าสุดในโฟลเดอร์นั้นให้ทีมดูได้ จะบอกได้ว่าติดที่การ์ดจอหรืออย่างอื่น
- เครื่องที่ใช้ได้: Windows 10 หรือ 11 แบบ 64 บิต และการ์ดจอที่รองรับ OpenGL 3.3 หรือ DirectX 11
  เครื่องเก่ามากอาจไม่ไหว
- ถ้า PC ไม่ไหวจริง ๆ: ไฟล์ .apk ใน release เดียวกันเล่นบนมือถือ Android ได้แล้ว (ทดสอบแล้วบนมือถือจอ Mali-G52)
  ใช้มือถือไปก่อนระหว่างที่ทีมดูเรื่อง PC ให้
