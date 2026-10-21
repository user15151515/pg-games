// Genera bomba/words.txt y bomba/syllables.json a partir de an-array-of-spanish-words.
// Uso: npm install && node tools/build-words.mjs
import { readFileSync, writeFileSync } from 'node:fs';

const raw = JSON.parse(readFileSync('node_modules/an-array-of-spanish-words/index.json', 'utf8'));

// Misma normalización que en el juego: minúsculas, sin acentos, conserva la ñ.
function norm(s) {
  let o = '';
  s = s.toLowerCase();
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    o += ch === 'ñ' ? 'ñ' : ch.normalize('NFD')[0];
  }
  return o;
}

const set = new Set();
for (const w of raw) {
  const n = norm(w);
  if (/^[a-zñ]{2,30}$/.test(n)) set.add(n);
}
const words = [...set].sort();
writeFileSync('bomba/words.txt', words.join('\n'));
console.log('palabras:', words.length);

// Cuenta de palabras que contienen cada fragmento de 2 y 3 letras.
const counts = new Map();
for (const w of words) {
  const seen = new Set();
  for (const k of [2, 3]) {
    for (let i = 0; i + k <= w.length; i++) seen.add(w.slice(i, i + k));
  }
  for (const s of seen) counts.set(s, (counts.get(s) || 0) + 1);
}

const EASY_MIN = 3000;
const NORMAL_MIN = 800;
const HARD_MIN = 150;
const out = { easy: [], normal: [], hard: [] };
for (const [s, n] of counts) {
  if (n >= EASY_MIN) out.easy.push(s);
  else if (n >= NORMAL_MIN) out.normal.push(s);
  else if (n >= HARD_MIN) out.hard.push(s);
}
for (const k of Object.keys(out)) out[k].sort();
writeFileSync('bomba/syllables.json', JSON.stringify(out));
console.log('sílabas:', Object.fromEntries(Object.entries(out).map(([k, v]) => [k, v.length])));
console.log('ejemplos easy:', out.easy.slice(0, 15).join(' '));
console.log('ejemplos hard:', out.hard.slice(0, 15).join(' '));

// ---- Palabras de ejemplo (con tildes) para el resumen final ----
// Candidatas: lemas del diccionario hunspell (dictionary-es) que también valen en el juego.
// Orden: por tamaño de "familia" (cuántas formas de la palabra existen en el diccionario grande),
// que favorece palabras de uso corriente frente a formas raras.
const big = words; // ya ordenado
const bigSet = new Set(big);
const lowerBound = x => { let lo = 0, hi = big.length; while (lo < hi) { const m = (lo + hi) >> 1; if (big[m] < x) lo = m + 1; else hi = m; } return lo; };
const family = p => lowerBound(p + '￿') - lowerBound(p);
const lemmas = readFileSync('node_modules/dictionary-es/index.dic', 'utf8').split('\n').slice(1)
  .map(l => l.split('/')[0].trim()).filter(w => /^[a-záéíóúüñ]{5,9}$/.test(w));
const info = [];
const seenN = new Set();
for (const w of lemmas) {
  const n = norm(w);
  if (!bigSet.has(n) || seenN.has(n)) continue;
  seenN.add(n);
  const stem = n.replace(/(ar|er|ir)$/, '').replace(/[aeo]s?$/, '');
  info.push({ w, n, score: family(stem) });
}
const examples = {};
for (const s of [...out.easy, ...out.normal, ...out.hard]) {
  const c = info.filter(x => x.n.includes(s)).sort((a, b) => b.score - a.score).slice(0, 6).map(x => x.w);
  if (c.length) examples[s] = c;
}
writeFileSync('bomba/examples.json', JSON.stringify(examples));
console.log('ejemplos para', Object.keys(examples).length, 'de', out.easy.length + out.normal.length + out.hard.length, 'sílabas');
