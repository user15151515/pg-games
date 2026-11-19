# Genera bomba/en/words.txt, bomba/en/syllables.json y bomba/en/examples.json (Bomba en inglés).
# Uso: npm install && pip install wordfreq && python3 tools/build-words-en.py
#
# Diccionario: an-array-of-english-words (~275.000 formas, con plurales y conjugaciones) más los lemas en
# minúscula del diccionario hunspell en_US (dictionary-en) que faltan y que son de uso real según wordfreq
# (selfie, emoji, blockchain...), con su plural cuando hunspell lo admite. Sin nombres propios ni abreviaturas.
# Ejemplos del resumen final: las palabras más frecuentes (wordfreq) que contienen cada sílaba.
import json, re
from collections import Counter
from wordfreq import zipf_frequency

base = set(json.load(open('node_modules/an-array-of-english-words/index.json')))
words = {w for w in base if re.fullmatch('[a-z]{2,30}', w)}

extra = set()
for line in open('node_modules/dictionary-en/index.dic').read().split('\n')[1:]:
    w, _, flags = line.strip().partition('/')
    if not re.fullmatch('[a-z]{4,30}', w) or w in words or not re.search('[aeiouy]', w):
        continue
    if zipf_frequency(w, 'en') < 2.0:
        continue
    extra.add(w)
    if 'S' in flags:
        pl = w + ('es' if re.search('(s|x|z|ch|sh)$', w) else 's')
        if zipf_frequency(pl, 'en') > 0:
            extra.add(pl)
words |= extra
words = sorted(words)
open('bomba/en/words.txt', 'w').write('\n'.join(words))
print('palabras:', len(words), '(añadidas', len(extra), ')')

counts = Counter()
for w in words:
    seen = set()
    for k in (2, 3):
        for i in range(len(w) - k + 1):
            seen.add(w[i:i + k])
    counts.update(seen)

# Umbrales elegidos para que cada grupo tenga un tamaño parecido al de español (unas 600, 880 y 1.230 sílabas).
EASY_MIN, NORMAL_MIN, HARD_MIN = 1300, 450, 150
out = {'easy': [], 'normal': [], 'hard': []}
for s, n in counts.items():
    if n >= EASY_MIN: out['easy'].append(s)
    elif n >= NORMAL_MIN: out['normal'].append(s)
    elif n >= HARD_MIN: out['hard'].append(s)
for k in out: out[k].sort()
json.dump(out, open('bomba/en/syllables.json', 'w'), separators=(',', ':'))
print('sílabas:', {k: len(v) for k, v in out.items()})

# Ejemplos: palabras de 5 a 9 letras ordenadas por frecuencia de uso
cand = [(w, zipf_frequency(w, 'en')) for w in words if 5 <= len(w) <= 9]
cand = [x for x in cand if x[1] >= 2.5]
cand.sort(key=lambda x: -x[1])
examples = {}
for s in out['easy'] + out['normal'] + out['hard']:
    c = [w for w, _ in cand if s in w][:6]
    if c: examples[s] = c
json.dump(examples, open('bomba/en/examples.json', 'w'), separators=(',', ':'))
print('ejemplos para', len(examples), 'de', sum(len(v) for v in out.values()), 'sílabas')
