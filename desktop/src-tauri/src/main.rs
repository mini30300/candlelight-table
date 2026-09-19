// หน้าต่างเดียว ชี้ไปที่ /app บนเซิร์ฟเวอร์เดียวกับที่มือถือใช้ (ดู tauri.conf.json)
// ตัวแอพฝั่ง Rust จึงไม่ต้องรู้อะไรเลย — ไม่มี IPC ไม่มีปลั๊กอิน ไฟล์ .exe เลยเล็ก
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    tauri::Builder::default()
        .run(tauri::generate_context!())
        .expect("เปิดหน้าต่าง Candlelight Table ไม่สำเร็จ");
}
