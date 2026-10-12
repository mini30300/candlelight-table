class_name Version
extends RefCounted
## เลขรุ่นของกติกาและแอป (ดู ARCHITECTURE §4): ทุกเครื่องในห้องต้องมี RULES_V เท่ากัน

## รุ่นกติกา: เปลี่ยนเมื่อกติกาหรือข้อมูลเปลี่ยน (ต้องตรงกับ BT_RULES ของเซิร์ฟเวอร์)
const RULES_V := 10
## รุ่นแอปที่ผู้เล่นเห็น: ขยับทุกครั้งที่ออกรุ่นใหม่
const APP_VER := "ใหม่ 0.1"
## แฮชของ data/*.json (เครื่องมือ lint ข้อมูลเป็นคนเติม)
const DATA_HASH := "5a98df1ca41da395ec3fe8def45b250ec5c708015b18531f22c7c5e5a6e4c42a"
## ชื่อโปรโตคอลบนสาย
const PROTO := "bt"
