#!/bin/bash
# vídeo + trilha + narração (a música abaixa quando a voz entra) e versões do site
set -e
S=/tmp/claude-0/-home-user-aura-perfumes-semijoias/31e5b5ad-f903-5c9b-aace-6a0c76221f7d/scratchpad
O=$S/mg/out; D=/home/user/aura-perfumes-semijoias/costa-usinagem
ffmpeg -v error -y -f concat -safe 0 -i $O/v60.list -i $O/trilha.wav -i $S/tts/voz.wav -filter_complex "
 [1:a]aresample=48000,volume=0.9[mus];
 [2:a]aresample=48000,highpass=f=85,equalizer=f=250:t=q:w=1.2:g=-2,equalizer=f=3200:t=q:w=1.5:g=3,
      acompressor=threshold=-20dB:ratio=3.5:attack=4:release=90:makeup=2,asplit=2[voz][sc];
 [mus][sc]sidechaincompress=threshold=0.015:ratio=9:attack=12:release=380[mduck];
 [mduck]volume=0.62[m2];
 [voz][m2]amix=inputs=2:normalize=0:duration=longest,loudnorm=I=-14:TP=-1.5:LRA=9[a]" \
 -map 0:v -map "[a]" -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -r 60 \
 -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart $D/video/costa-usinagem-motion-voz-1080x1920.mp4
# versão só com música (sem narração)
ffmpeg -v error -y -f concat -safe 0 -i $O/v60.list -i $O/trilha.wav -map 0:v -map 1:a \
 -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -r 60 -af "loudnorm=I=-14:TP=-1.5:LRA=11" \
 -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart $D/video/costa-usinagem-motion-1080x1920.mp4
# versão leve para o site (com voz)
ffmpeg -v error -y -i $D/video/costa-usinagem-motion-voz-1080x1920.mp4 -vf "scale=720:1280,fps=30" -c:v libx264 -preset slow -crf 25 \
 -c:a aac -b:a 128k -movflags +faststart $D/video/costa-usinagem.mp4
ffmpeg -v error -y -ss 2.9 -i $D/video/costa-usinagem-motion-voz-1080x1920.mp4 -frames:v 1 -vf scale=720:1280 -q:v 4 $D/video/capa.jpg
