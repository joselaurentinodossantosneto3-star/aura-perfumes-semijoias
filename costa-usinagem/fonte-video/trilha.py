# Trilha sincronizada com o vídeo motion (120 bpm, lá menor). Só numpy.
import sys, wave, numpy as np
OUT = sys.argv[1]
SR = 44100; TOTAL = 49.0; N = int(SR * (TOTAL + 1)); BEAT = .5
rng = np.random.default_rng(3)
L = np.zeros(N); R = np.zeros(N)          # mix seco
RV = np.zeros(N)                           # envio para reverb
LD = np.zeros(N); RD = np.zeros(N)         # bateria (não sofre sidechain)
SC = np.ones(N)                            # envelope de "sidechain"

def add(sig, t, g=1.0, pan=0.0, rev=0.0, dr=False):
    i = int(t * SR)
    if i >= N: return
    j = min(N, i + len(sig)); s = sig[:j - i] * g
    A, B = (LD, RD) if dr else (L, R)
    A[i:j] += s * (1 - max(pan, 0)); B[i:j] += s * (1 + min(pan, 0)); RV[i:j] += s * rev
def mid(n): return 440 * 2 ** ((n - 69) / 12)
def tt(d): return np.arange(int(d * SR)) / SR

def additive(f, d, nh=18, bright=1.0, decay=3.0, hdecay=.35, att=.004, kind='saw'):
    t = tt(d); s = np.zeros_like(t)
    for k in range(1, nh + 1):
        if f * k > 15000: break
        if kind == 'square' and k % 2 == 0: continue
        a = (1 / k) * bright ** (k - 1)
        s += a * np.sin(2 * np.pi * f * k * t + rng.uniform(0, 6.28)) * np.exp(-t * decay * (1 + hdecay * (k - 1)))
    return s * np.minimum(1, t / att)
def kick():
    t = tt(.5); f = 42 + 110 * np.exp(-t * 32); ph = 2 * np.pi * np.cumsum(f) / SR
    return np.tanh(1.6 * np.sin(ph) * np.exp(-t * 6.5)) * .95 + rng.normal(0, 1, len(t)) * np.exp(-t * 250) * .12
def hp(x, k=3):  # passa-altas grosseiro
    return x - np.convolve(x, np.ones(k) / k, 'same')
def lp(x, k=8): return np.convolve(x, np.ones(k) / k, 'same')
def clap():
    t = tt(.35); n = hp(rng.normal(0, 1, len(t)), 6)
    env = np.zeros_like(t)
    for o in (0, .011, .022): env += np.where(t >= o, np.exp(-(t - o) * 90), 0)
    env += np.exp(-t * 14) * .5
    return n * env * .3
def hat(open_=False):
    t = tt(.3 if open_ else .07); n = hp(rng.normal(0, 1, len(t)), 2)
    return n * np.exp(-t * (14 if open_ else 70)) * .11
def tick(f=3200):
    t = tt(.04); return np.sin(2 * np.pi * f * t) * np.exp(-t * 120) * .25 + hp(rng.normal(0, 1, len(t)), 2) * np.exp(-t * 300) * .15
def impact(big=1.0):
    t = tt(3.0)
    boom = np.sin(2 * np.pi * (34 + 60 * np.exp(-t * 9)) * t) * np.exp(-t * 1.4)
    crack = lp(rng.normal(0, 1, len(t)), 3) * np.exp(-t * 9) * .6
    metal = sum(np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, d in ((523, 3), (1187, 4), (1913, 6), (2741, 8))) * .07
    return (np.tanh(boom * 1.4) * .9 + crack + metal) * big
def whoosh(d=.7, up=True):
    t = tt(d); n = rng.normal(0, 1, len(t))
    # varredura: mistura gradual de ruído grave -> agudo
    a = lp(n, 24); b = hp(n, 3); m = t / d if up else 1 - t / d
    env = np.sin(np.pi * t / d) ** 2
    return (a * (1 - m) * 1.6 + b * m) * env * .22
def riser(d):
    t = tt(d); n = rng.normal(0, 1, len(t)); m = (t / d) ** 2
    s = (lp(n, 30) * (1 - m) * 1.5 + hp(n, 3) * m) * (t / d) ** 2 * .22
    tone = np.sin(2 * np.pi * np.cumsum(220 + 660 * (t / d) ** 2) / SR) * (t / d) ** 3 * .06
    return s + tone
def duck(t, depth=.65, rel=.22):  # sidechain a partir de t
    i = int(t * SR); n = int(rel * 1.6 * SR); j = min(N, i + n)
    env = 1 - depth * np.exp(-np.arange(j - i) / SR / (rel / 3))
    SC[i:j] = np.minimum(SC[i:j], env)

PROG = [(45, [57, 60, 64, 69]), (41, [53, 57, 60, 65]), (48, [55, 60, 64, 67]), (43, [55, 59, 62, 67])]
def chord_at(t): return PROG[int(t // 2) % 4]

# -------- abertura 0–4
add(lp(rng.normal(0, 1, int(4 * SR)), 60) * np.linspace(0, 1, int(4 * SR)) * .25, 0)            # rumor
for nn in (33, 45):
    d = 4.2; add(additive(mid(nn), d, nh=6, decay=.25, hdecay=.2, att=1.2) * .16, 0, rev=.3)
add(riser(1.15), 0, .9)
add(impact(1.0), 1.15, rev=.5, dr=True); duck(1.15, .8, .5)
for k in range(5): add(tick(2600 + k * 180), 1.45 + k * .07, .9, pan=-.4 + k * .2, dr=True)
for k in range(8): add(tick(3400 + k * 90), 1.75 + k * .045, .6, pan=.4 - k * .1, dr=True)
add(whoosh(.6), 2.0, .8)
add(riser(1.4), 2.6, 1.0)
# -------- groove principal
def groove(t0, t1, kick_on=True, hats=True, bass=True, arp=True, pad=True, claps=True):
    b = t0
    while b < t1 - 1e-6:
        beat = int(round(b / BEAT))
        root, ch = chord_at(b)
        if kick_on: add(kick(), b, 1.0, dr=True); duck(b)
        if claps and beat % 2 == 1: add(clap(), b, .9, pan=-.05, rev=.25, dr=True)
        if hats:
            for s in range(4):
                add(hat(open_=(s == 2)), b + s * BEAT / 4, .8 if s == 2 else .55, pan=.25, dr=True)
        if bass:
            for e in range(2):
                n = root - 12 + (12 if e == 1 else 0)
                add(additive(mid(n), BEAT / 2 - .01, nh=10, bright=.8, decay=5, hdecay=.5, att=.003) * .5, b + e * BEAT / 2)
        if arp:
            for s in range(4):
                n = ch[(beat * 4 + s) % 4] + 12
                add(additive(mid(n), .3, nh=12, bright=.82, decay=9, hdecay=.45) * .09, b + s * BEAT / 4, pan=(-.35 if s % 2 else .35), rev=.35)
        if pad and abs((b % 2.0)) < 1e-6:
            for k, n in enumerate(ch[:3]):
                for det in (-.004, .004):
                    add(additive(mid(n) * (1 + det), 2.05, nh=8, bright=.7, decay=.15, hdecay=.15, att=.25) * .045, b, pan=(-.5 + k * .5), rev=.5)
        b += BEAT
# manifesto 4–9: entra a bateria
add(impact(1.1), 4.0, rev=.4, dr=True); duck(4.0, .9, .4)
groove(4.0, 7.0, arp=False)
for tw, g in ((4.5, .55), (5.0, .7), (5.5, .5), (6.0, .6)): add(impact(g * .6), tw, rev=.3, dr=True)
add(whoosh(.35, up=True), 4.85, .9)
add(whoosh(.45, up=False), 6.75, .9)
# contador: ticks quando o número muda (mesma curva do vídeo)
u = np.linspace(0, 2, 4000); cp = 1 - (1 - np.clip((u - .25) / 1.2, 0, 1)) ** 3; n = np.round(30 * cp)
for k in np.nonzero(np.diff(n))[0]: add(tick(2200 + 40 * n[k + 1]), 6.95 + u[k + 1], .8, dr=True)
groove(7.0, 9.0, kick_on=False, claps=False, arp=False, hats=False)
add(impact(.8), 6.95 + 1.45, rev=.5, dr=True)
add(riser(.9), 8.1, .8)
# título 9–10
add(impact(.9), 9.0, rev=.4, dr=True); duck(9.0, .8, .4)
add(whoosh(.8), 9.0, .9)
# serviços 10–35
groove(10.0, 35.0)
for k in range(10): add(impact(.35), 10 + k * 2.5, rev=.3, dr=True)
# mosaico 35–38: virada e subida
groove(35.0, 36.5, arp=True)
add(impact(.8), 35.0, rev=.4, dr=True)
for k in range(12):
    tt0 = 36.5 + k * (1.5 / 12); add(clap(), tt0, .35 + k * .05, rev=.2, dr=True)
add(riser(1.5), 36.5, 1.1)
# clientes 38–41.5
add(impact(1.0), 38.0, rev=.5, dr=True); duck(38.0, .9, .5)
groove(38.0, 41.5, kick_on=True, claps=True, bass=True, arp=False)
add(riser(.9), 40.6, .8)
# chamada 41,5–46
add(impact(1.1), 41.5, rev=.5, dr=True); duck(41.5, .9, .5)
groove(41.5, 46.0)
t = tt(.12); add(np.sin(2 * np.pi * (900 - 600 * t / .12) * t) * np.exp(-t * 30) * .5, 43.5)   # toque no botão
add(tick(4200), 43.5, 1.0, dr=True)
add(riser(.9), 45.1, .9)
# encerramento 46–49
add(impact(1.3), 46.0, rev=.7, dr=True); duck(46.0, .9, .8)
for nn in (33, 45, 57, 60, 64, 69, 72):
    add(additive(mid(nn), 3.5, nh=10, bright=.75, decay=.7, hdecay=.3, att=.01) * .07, 46.0, pan=rng.uniform(-.4, .4), rev=.6)
for k, nn in enumerate((69, 72, 76, 81)): add(additive(mid(nn), 1.2, nh=6, decay=3) * .05, 46.15 + k * .12, pan=-.3 + k * .2, rev=.6)

# -------- reverb (convolução com cauda de ruído) + mix
ir_t = tt(2.2); ir = rng.normal(0, 1, (2, len(ir_t))) * np.exp(-ir_t * 3.2); ir[:, :int(.012 * SR)] = 0; ir /= np.abs(ir).sum(1, keepdims=True) / 25
def conv(x, h):
    n = 1 << int(np.ceil(np.log2(len(x) + len(h))))
    return np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(h, n), n)[:len(x)]
rvL, rvR = conv(RV, ir[0]) * .35, conv(RV, ir[1]) * .35
# sidechain só nos sons sustentados: aplicado ao mix inteiro de forma suave
L2 = L * (0.35 + .65 * SC) + LD + rvL; R2 = R * (0.35 + .65 * SC) + RD + rvR
m = np.stack([L2, R2], 1)
m = np.tanh(m * 1.25) / np.tanh(1.25)
fade_i = int((TOTAL - .9) * SR); m[fade_i:int(TOTAL * SR)] *= np.linspace(1, 0, int(TOTAL * SR) - fade_i)[:, None]; m[int(TOTAL * SR):] = 0
m = m[:int(TOTAL * SR)]
m *= .9 / np.abs(m).max()
w = wave.open(OUT, 'wb'); w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes((m * 32767).astype('<i2').tobytes()); w.close()
print('ok', len(m) / SR)
