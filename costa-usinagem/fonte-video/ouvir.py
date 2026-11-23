# Transcreve cada fala com Whisper (sherpa-onnx) para conferir a pronúncia.
import sys, glob, soundfile as sf, numpy as np, sherpa_onnx
M = sys.argv[1]; pat = sys.argv[2]
r = sherpa_onnx.OfflineRecognizer.from_whisper(encoder=f'{M}/small-encoder.int8.onnx', decoder=f'{M}/small-decoder.int8.onnx', tokens=f'{M}/small-tokens.txt', language='pt', task='transcribe', num_threads=4)
for f in sorted(glob.glob(pat)):
    a, sr = sf.read(f, dtype='float32')
    if a.ndim > 1: a = a.mean(1)
    s = r.create_stream(); s.accept_waveform(sr, a); r.decode_stream(s)
    print(f.split('/')[-1], '|', s.result.text.strip())
