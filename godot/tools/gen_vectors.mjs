#!/usr/bin/env node
// gen_vectors.mjs — writes godot/tests/unit/fixtures/vectors.json: the JavaScript truth that core/fx.gd must
// reproduce (Math.round, toFixed(1)/toFixed(2) on milli-inch integers, exact integer square roots) plus
// known-answer vectors for core/rng.gd (PCG32, computed in BigInt) and core/hash.gd (FNV-1a 64, ihash2/ihash3).
// Node only, no dependencies:   node godot/tools/gen_vectors.mjs
// Keep the output under 200 KB; the tests read it with JSON.parse_string, so every number stays below 2^53
// and 64-bit values travel as strings (decimal) or 16-char hex.

import { writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '..', 'tests', 'unit', 'fixtures', 'vectors.json');
const M64 = (1n << 64n) - 1n;
const M32 = (1n << 32n) - 1n;
const SAFE = 2 ** 52; // every plain JSON number in the file stays below this

// --- helpers -------------------------------------------------------------------------------------------------

function hex64(v) { return BigInt.asUintN(64, v).toString(16).padStart(16, '0'); }

function assertSafe(n, what) {
	if (!Number.isInteger(n) || Math.abs(n) > SAFE) throw new Error(`${what}: ${n} is not a safe integer`);
	return n;
}

// exact floor(sqrt(n)) for a BigInt n >= 0 (Newton from above)
function isqrtBig(n) {
	if (n < 2n) return n;
	let x = 1n << BigInt(Math.ceil(n.toString(2).length / 2));
	for (;;) {
		const y = (x + n / x) >> 1n;
		if (y >= x) return x;
		x = y;
	}
}

// FNV-1a 64 over bytes (Uint8Array / array of numbers)
const FNV_BASIS = 14695981039346656037n;
const FNV_PRIME = 1099511628211n;
function fnv1a64(bytes) {
	let h = FNV_BASIS;
	for (const b of bytes) {
		h ^= BigInt(b);
		h = (h * FNV_PRIME) & M64;
	}
	return h;
}
function int64Bytes(ints) { // each int64 as 8 little-endian bytes
	const out = [];
	for (const s of ints) {
		let v = BigInt.asUintN(64, BigInt(s));
		for (let i = 0; i < 8; i++) { out.push(Number(v & 255n)); v >>= 8n; }
	}
	return out;
}
function fnvStr(s) { return fnv1a64(Buffer.from(s, 'utf8')); }

// PCG32 (Melissa O'Neill's pcg32_random_r / pcg32_srandom_r), state and increment as uint64
const PCG_MULT = 6364136223846793005n;
class Pcg {
	constructor(seed, stream) {
		this.inc = ((fnvStr(stream) << 1n) | 1n) & M64;
		this.state = 0n;
		this.step();
		this.state = (this.state + BigInt.asUintN(64, BigInt(seed))) & M64;
		this.step();
	}
	step() { this.state = (this.state * PCG_MULT + this.inc) & M64; }
	next() {
		const old = this.state;
		this.step();
		const xs = (((old >> 18n) ^ old) >> 27n) & M32;
		const rot = old >> 59n;
		return Number(((xs >> rot) | (xs << ((32n - rot) & 31n))) & M32);
	}
	bounded(n) { // classic unbiased rejection sampling: threshold = (2^32 - n) % n
		const t = Number((4294967296n - BigInt(n)) % BigInt(n));
		for (;;) { const r = this.next(); if (r >= t) return r % n; }
	}
}

// ihash2 / ihash3: v10's own 32-bit mixers (lowbias32 finaliser by Chris Wellons over xor-multiplied inputs)
function mix32(h) {
	h ^= h >> 16n; h = (h * 0x7feb352dn) & M32;
	h ^= h >> 15n; h = (h * 0x846ca68bn) & M32;
	h ^= h >> 16n;
	return h;
}
const u32 = (v) => BigInt.asUintN(32, BigInt(v));
function ihash2(x, y, seed) {
	let h = mix32(u32(seed) ^ 0x9e3779b9n);
	h = mix32(h ^ ((u32(x) * 0x85ebca77n) & M32));
	h = mix32(h ^ ((u32(y) * 0xc2b2ae3dn) & M32));
	return Number(h);
}
function ihash3(x, y, z, seed) {
	let h = mix32(u32(seed) ^ 0x9e3779b9n);
	h = mix32(h ^ ((u32(x) * 0x85ebca77n) & M32));
	h = mix32(h ^ ((u32(y) * 0xc2b2ae3dn) & M32));
	h = mix32(h ^ ((u32(z) * 0x27d4eb2fn) & M32));
	return Number(h);
}

// --- js_round: Math.round(num / den), half toward +inf ------------------------------------------------------

const jsRound = { ranges: [], extra: [] };
for (const den of [1, 2, 10, 100, 1000]) {
	const from = -700, to = 700, r = [];
	for (let num = from; num <= to; num++) r.push(Math.round(num / den));
	jsRound.ranges.push({ den, from, r });
}
for (const [num, den] of [
	[1e15 + 5, 10], [-(1e15 + 5), 10], [2 ** 50 + 1, 2], [-(2 ** 50) - 1, 2], [123456789, 1000], [-123456789, 1000],
	[999999999999, 1000], [-999999999999, 1000], [2 ** 52 - 1, 1], [-(2 ** 52) + 1, 1], [180000 * 1000 + 500, 1000],
	[-(180000 * 1000 + 500), 1000], [4999999999, 10000], [-4999999999, 10000], [5, 3], [-5, 3], [7, 7], [-7, 7],
	[1, 7], [-1, 7], [3, 7], [-3, 7], [50, 100], [-50, 100], [150, 100], [-150, 100], [250, 100], [-250, 100],
]) jsRound.extra.push([assertSafe(num, 'js_round num'), den, Math.round(num / den)]);

// --- toFixed on milli-inches: (mi / 1000).toFixed(1) and .toFixed(2) ----------------------------------------

const TF_FROM = -1500, TF_TO = 1500;
const f1 = [], f2 = [];
for (let mi = TF_FROM; mi <= TF_TO; mi++) { f1.push((mi / 1000).toFixed(1)); f2.push((mi / 1000).toFixed(2)); }
const tfExtra = [];
const tfSet = new Set();
for (let odd = 1; odd <= 199; odd += 2) { tfSet.add(125 * odd); tfSet.add(-125 * odd); } // exact binary ties
for (let mi = 1005; mi <= 3005; mi += 10) { tfSet.add(mi); tfSet.add(-mi); }           // decimal ties, inexact doubles
for (let mi = 1050; mi <= 9950; mi += 100) { tfSet.add(mi); tfSet.add(-mi); }
for (const mi of [2675, 1005, 1015, 8125, 999995, -999995, 999950, -999950, 1234565, 1234575, 100000005, 100000015,
	100000125, 180000500, 180000050, 4503599627370501, -4503599627370501, 4503599627370500, 2 ** 52 - 5,
	2 ** 52 - 50, 1125899906842625, 1125899906842655, 35184372088835, 35184372088832125, -35184372088832125,
	4, -4, 40, -40, 49, -49, 51, -51, 500, -500, 999, -999, 1000, -1000, 100000, -100000]) tfSet.add(mi);
let lcg = 12345n; // a tiny LCG spreads samples over 1e6..1e12 (deterministic, no Math.random)
for (let i = 0; i < 150; i++) {
	lcg = (lcg * 6364136223846793005n + 1442695040888963407n) & M64;
	const span = [1e6, 1e8, 1e10, 1e12][i & 3];
	const mi = Number(lcg >> 20n) % span;
	tfSet.add(mi); tfSet.add(-mi);
	tfSet.add(mi - (mi % 10) + 5); // force a decimal tie near it
}
for (const mi of [...tfSet].sort((a, b) => a - b)) {
	if (Math.abs(mi) > SAFE) continue;
	tfExtra.push([mi, (mi / 1000).toFixed(1), (mi / 1000).toFixed(2)]);
}

// --- isqrt ---------------------------------------------------------------------------------------------------

const isqrtSmall = [];
for (let n = 0; n <= 5000; n++) isqrtSmall.push(Number(isqrtBig(BigInt(n))));
const bigNs = new Set(['65000000000', '64800000000', '64800000001', '9223372036854775807', '4611686018427387904',
	'4611686018427387903', '9007199254740993', '9007199254740992', '9007199254740991', '1000000000000000000',
	'999999999999999999', '32400000000', '180000000', '3037000499', '9223372030926249001', '9223372030926249000',
	'9223372030926249002', '4000000000000000000', '6917529027641081856', '1152921504606846976', '281474976710656']);
for (let r = 1n; r < 3037000499n; r = r * 3n + 7n) { // perfect squares and their neighbours up to 2^63
	const sq = r * r;
	bigNs.add(sq.toString()); bigNs.add((sq - 1n).toString()); bigNs.add((sq + 1n).toString());
}
const isqrtBigPairs = [...bigNs].map((s) => [s, isqrtBig(BigInt(s)).toString()]);

// --- PCG32 known answers ---------------------------------------------------------------------------------------

const pcg = [];
for (const [seed, stream] of [[1, 'terrain'], [1, 'props'], [42, 'objectives'], [99999, 'armies'], [7, 'deploy'],
	[12345, 'bot:0'], [12345, 'bot:1'], [2024, 'fallback:17:atk'], [0, 'terrain'], [2 ** 52 - 3, 'terrain'],
	[-1, 'terrain'], [1, 'fallback:1:wnd']]) {
	const p = new Pcg(seed, stream);
	const first = []; for (let i = 0; i < 16; i++) first.push(p.next());
	const state16 = hex64(p.state);
	const d6 = []; for (let i = 0; i < 24; i++) d6.push(1 + p.bounded(6));
	const b100 = []; for (let i = 0; i < 8; i++) b100.push(p.bounded(100));
	const bbig = []; for (let i = 0; i < 4; i++) bbig.push(p.bounded(4294967295));
	let at1000 = 0; for (let i = 0; i < 1000; i++) at1000 = p.next();
	pcg.push({ seed, stream, inc: hex64(p.inc), first, state16, d6, b100, bbig, at1000 });
}

// --- FNV-1a 64 -------------------------------------------------------------------------------------------------

const fnvInts = [[], ['0'], ['1'], ['-1'], ['1', '2', '3'], ['4611686018427387904', '-4611686018427387904'],
	['10', '0', '7', '-3', '180000', '1000'], ['9223372036854775807', '-9223372036854775808'], ['255', '256'],
	['10', '1', '0', '0', '0', '0', '0', '0']].map((v) => ({ v, hex: hex64(fnv1a64(int64Bytes(v))) }));
const fnvStrs = ['', 'a', 'ab', 'terrain', 'props', 'objectives', 'armies', 'deploy', 'bot:0', 'bot:7',
	'fallback:17:atk', 'โต๊ะเทียน', 'ใหม่ 0.1', 'hello world'].map((s) => ({ s, hex: hex64(fnvStr(s)) }));

// --- ihash2 / ihash3 ----------------------------------------------------------------------------------------------

const ih2 = [], ih3 = [];
const samples = [0, 1, -1, 2, 7, -7, 100, 65535, 65536, 2147483647, -2147483648, 4294967295, 4294967296,
	180000, -180000, 2 ** 40 + 3, -(2 ** 40) - 3, 2 ** 52 - 1];
for (const seed of [0, 1, 99999, -5]) {
	for (const x of samples) for (const y of [0, 1, -1, 180000, 2 ** 40 + 3]) ih2.push([x, y, seed, ihash2(x, y, seed)]);
	for (const z of samples) ih3.push([3, -4, z, seed, ihash3(3, -4, z, seed)]);
}
ih3.push([1, 2, 3, 4, ihash3(1, 2, 3, 4)], [2, 1, 3, 4, ihash3(2, 1, 3, 4)], [3, 2, 1, 4, ihash3(3, 2, 1, 4)]);

// --- write -------------------------------------------------------------------------------------------------------

const doc = {
	about: 'generated by godot/tools/gen_vectors.mjs — do not edit; numbers are exact (< 2^53), 64-bit values are strings',
	node: process.version,
	js_round: jsRound,
	to_fixed: { from: TF_FROM, f1: f1.join(','), f2: f2.join(','), extra: tfExtra },
	isqrt: { small: isqrtSmall, big: isqrtBigPairs },
	pcg32: pcg,
	fnv: { ints: fnvInts, strs: fnvStrs },
	ihash: { h2: ih2, h3: ih3 },
};
const text = JSON.stringify(doc);
mkdirSync(dirname(OUT), { recursive: true });
writeFileSync(OUT, text + '\n');
console.log(`wrote ${OUT} (${(text.length / 1024).toFixed(1)} KB): ${tfExtra.length} toFixed extras, ${isqrtBigPairs.length} big isqrt, ${pcg.length} PCG streams, ${ih2.length + ih3.length} ihash`);
