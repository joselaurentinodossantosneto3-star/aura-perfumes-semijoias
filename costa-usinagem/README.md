# Costa Usinagem · site e vídeo

Feito a partir do vídeo de apresentação da Costa Usinagem (mecânica industrial, São Vicente-SP, desde 1992).

## Site (motion design)
- `index.html`: site de página única com animações (abertura com engrenagem e logo, títulos revelados, galeria de trabalhos com rolagem lateral e marcações técnicas que se desenham, antes/depois guiado pela rolagem, processo em 4 passos, clientes em faixa, botões magnéticos, cursor próprio e rolagem suave). Quem prefere menos movimento no sistema vê o site sem animação.
- `js/`: GSAP 3.12.5 + ScrollTrigger e Lenis 1.1.13 (animação e rolagem suave), servidos junto com o site.
- `costa-usinagem-completo.html`: o mesmo site num arquivo só, com fotos, vídeo e scripts embutidos. Abre direto no celular ou no computador.
- `img/`: fotos e logos recortados do vídeo original.
- Para publicar: suba a pasta inteira (`index.html`, `img/`, `video/`, `js/`) em qualquer hospedagem estática, ou só o arquivo completo.

## Vídeos
- `video/costa-usinagem-motion-voz-1080x1920.mp4`: motion design com narração (50 s, vertical, 60 fps). É o que aparece no topo do site.
- `video/costa-usinagem-motion-1080x1920.mp4`: o mesmo, só com música.
- `video/costa-usinagem-reels-1080x1920.mp4`: primeira versão (45 s).
- `video/costa-usinagem.mp4` e `video/capa.jpg`: versão leve usada no site.

## Como o vídeo é gerado (`fonte-video/`)
- `motion.html` + `render.js`: animação desenhada quadro a quadro no navegador (Playwright) e codificada com ffmpeg.
- `trilha.py`: trilha sincronizada com a animação (só numpy).
- `roteiro.json`, `narrar.py`, `montar_voz.py`: narração em pt-BR com a voz neural Kokoro (pm_alex), cortada e encaixada na linha do tempo.
- `ouvir.py`: confere a narração transcrevendo com Whisper.
- `finalizar_voz.sh`: mixa voz e música (a música abaixa quando a voz entra) e gera as versões finais.
- Para regerar, coloque `img/` e `fonts/` (Archivo e Inter) ao lado de `motion.html`, e os modelos Kokoro ao lado de `narrar.py`.

As fotos vieram de um vídeo de 598×848, então ficam um pouco suaves em telas grandes. Com as fotos originais da oficina dá para trocar os arquivos em `img/` mantendo os mesmos nomes.
