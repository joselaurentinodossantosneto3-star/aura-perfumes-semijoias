# Gera cada fala da narração (pt-BR) e informa a duração de cada uma.
import sys, json, soundfile as sf
from kokoro_onnx import Kokoro
D = sys.argv[1]; voz = sys.argv[2]; vel = float(sys.argv[3])
k = Kokoro(D + '/kokoro-v1.0.onnx', D + '/voices-v1.0.bin')
FALAS = json.load(open(D + '/roteiro.json'))
out = []
for i, (ini, fim, txt) in enumerate(FALAS):
    a, sr = k.create(txt, voice=voz, speed=vel, lang='pt-br')
    f = f'{D}/{sys.argv[4]}/{voz}_{i:02d}.wav'; sf.write(f, a, sr)
    out.append((i, ini, fim, round(len(a) / sr, 2), txt))
    print(f'{i:02d} [{ini:5.1f}-{fim:5.1f}] janela {fim-ini:4.1f}s  fala {len(a)/sr:4.2f}s  {txt}')
