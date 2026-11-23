#!/bin/bash
# junta as partes, coloca a trilha (normalizada para redes sociais) e gera as versões do site
set -e
S=/tmp/claude-0/-home-user-aura-perfumes-semijoias/31e5b5ad-f903-5c9b-aace-6a0c76221f7d/scratchpad/mg/out
D=/home/user/aura-perfumes-semijoias/costa-usinagem
ffmpeg -v error -y -f concat -safe 0 -i $S/v60.list -i $S/trilha.wav -map 0:v -map 1:a \
  -c:v libx264 -preset slow -crf 18 -profile:v high -pix_fmt yuv420p -r 60 \
  -af "loudnorm=I=-14:TP=-1.5:LRA=11" -c:a aac -b:a 192k -ar 48000 -shortest -movflags +faststart \
  $D/video/costa-usinagem-motion-1080x1920.mp4
ffmpeg -v error -y -i $D/video/costa-usinagem-motion-1080x1920.mp4 -vf "scale=720:1280,fps=30" -c:v libx264 -preset slow -crf 25 \
  -c:a aac -b:a 128k -movflags +faststart $D/video/costa-usinagem.mp4
ffmpeg -v error -y -ss 2.9 -i $D/video/costa-usinagem-motion-1080x1920.mp4 -frames:v 1 -vf scale=720:1280 -q:v 4 $D/video/capa.jpg
ls -la $D/video
