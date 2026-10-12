class_name Hash
extends RefCounted
## แฮชจำนวนเต็มของ v10 (ARCHITECTURE §4): ihash2/ihash3 ตัวผสม 32 บิตสำหรับ noise และ FNV-1a 64 สำหรับ digest
## ตัวเลขมาสก์ให้อยู่ใน 32 บิตก่อนคูณ ผลคูณจึงอยู่ใน 64 บิต (ล้นแล้ววนก็ยังได้บิตล่างถูก)

const M32 := 4294967295
## FNV-1a 64: offset basis 14695981039346656037 เขียนแบบมีเครื่องหมาย
const FNV_BASIS := -3750763034362895579
const FNV_PRIME := 1099511628211
const HEX := "0123456789abcdef"


## ตัวผสมท้าย 32 บิต (lowbias32)
static func mix32(v: int) -> int:
	var h := v & M32
	h ^= h >> 16
	h = (h * 0x7FEB352D) & M32
	h ^= h >> 15
	h = (h * 0x846CA68B) & M32
	h ^= h >> 16
	return h


## แฮช 2 มิติ + เกลือ → 0..2^32-1 (ค่าติดลบหรือเกิน 32 บิตถูกมาสก์ก่อน)
static func ihash2(x: int, y: int, salt: int) -> int:
	var h := mix32((salt & M32) ^ 0x9E3779B9)
	h = mix32(h ^ (((x & M32) * 0x85EBCA77) & M32))
	h = mix32(h ^ (((y & M32) * 0xC2B2AE3D) & M32))
	return h


## แฮช 3 มิติ + เกลือ → 0..2^32-1
static func ihash3(x: int, y: int, z: int, salt: int) -> int:
	var h := mix32((salt & M32) ^ 0x9E3779B9)
	h = mix32(h ^ (((x & M32) * 0x85EBCA77) & M32))
	h = mix32(h ^ (((y & M32) * 0xC2B2AE3D) & M32))
	h = mix32(h ^ (((z & M32) * 0x27D4EB2F) & M32))
	return h


## FNV-1a 64 บิตของอาร์เรย์ int64 (แต่ละตัวเป็น 8 ไบต์ little-endian); ผลเป็น int64 มีเครื่องหมาย
static func fnv1a64(ints: PackedInt64Array) -> int:
	var h := FNV_BASIS
	for v: int in ints:
		for b: int in 8:
			h ^= (v >> (b * 8)) & 255
			h *= FNV_PRIME
	return h


## FNV-1a 64 บิตของสตริง (ไบต์ UTF-8)
static func fnv1a64_str(s: String) -> int:
	var h := FNV_BASIS
	for b: int in s.to_utf8_buffer():
		h ^= b
		h *= FNV_PRIME
	return h


## int64 เป็นฐานสิบหก 16 ตัวอักษร (มองเป็น unsigned)
static func hex64(v: int) -> String:
	var out := ""
	for i: int in 16:
		out += HEX[(v >> ((15 - i) * 4)) & 15]
	return out


## digest ของสถานะ = FNV-1a 64 ของอาร์เรย์ int เป็นฐานสิบหก 16 ตัว
static func digest_hex(ints: PackedInt64Array) -> String:
	return hex64(fnv1a64(ints))
