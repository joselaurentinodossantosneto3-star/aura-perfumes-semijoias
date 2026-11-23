# Corta o silêncio de cada fala, acelera só o necessário e monta a faixa de voz na linha do tempo (48 kHz).
import json, subprocess, soundfile as sf, numpy as np, sys
D = sys.argv[1]; TOTAL = float(sys.argv[2])
R = json.load(open(D + '/roteiro.json'))
INI = {1: 3.95, 3: 9.1, 4: 10.3, 16: 41.35, 17: 46.4}
SR = 48000; track = np.zeros(int(SR * (TOTAL + 1)))
def trim(a, sr, thr=.012):
    e = np.convolve(np.abs(a), np.ones(240) / 240, 'same'); idx = np.nonzero(e > thr)[0]
    return a[max(0, idx[0] - int(.03 * sr)): idx[-1] + int(.06 * sr)]
starts = [INI.get(i, r[0]) for i, r in enumerate(R)]
for i, (ini, fim, txt) in enumerate(R):
    a, sr = sf.read(f'{D}/final/pm_alex_{i:02d}.wav'); a = trim(a, sr)
    st = starts[i]; nxt = starts[i + 1] if i + 1 < len(R) else TOTAL - .5
    room = nxt - st - .08; dur = len(a) / sr
    tempo = min(1.15, max(1.0, dur / room))
    sf.write(f'{D}/ajust/t{i:02d}.wav', a, sr)
    subprocess.run(['ffmpeg', '-v', 'error', '-y', '-i', f'{D}/ajust/t{i:02d}.wav', '-af', f'atempo={tempo:.3f},aresample={SR}', f'{D}/ajust/f{i:02d}.wav'], check=True)
    b, _ = sf.read(f'{D}/ajust/f{i:02d}.wav')
    j = int(st * SR); track[j:j + len(b)] += b
    print(f'{i:02d} {st:5.2f}-{st + len(b) / SR:5.2f} (janela até {nxt:5.2f}) tempo {tempo:.2f}', 'SOBREPOE' if st + len(b) / SR > nxt else '')
track /= np.abs(track).max() / .95
sf.write(D + '/voz.wav', track[:int(SR * TOTAL)], SR)
