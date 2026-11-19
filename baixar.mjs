// Monta a pasta public/ para a Vercel. Com o repositório inteiro, copia o index.html daqui;
// quando só os arquivos pequenos são enviados, baixa o index.html da versão indicada em versao.txt.
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';

const REPO = 'joselaurentinodossantosneto3-star/aura-perfumes-semijoias';
mkdirSync('public', { recursive: true });
let html;
if (existsSync('index.html')) {
  html = readFileSync('index.html', 'utf8');
} else {
  const versao = existsSync('versao.txt') ? readFileSync('versao.txt', 'utf8').trim() : 'main';
  const r = await fetch(`https://raw.githubusercontent.com/${REPO}/${versao}/index.html`);
  if (!r.ok) throw new Error(`não deu para baixar o index.html (${r.status}) da versão ${versao}`);
  html = await r.text();
}
if (html.length < 500000 || !html.includes('__auraApp')) throw new Error('index.html inesperado: confira a versão');
writeFileSync('public/index.html', html);

// arquivos pequenos que acompanham a página (aplicativo instalável)
const versaoEst = existsSync('versao.txt') ? readFileSync('versao.txt', 'utf8').trim() : 'main';
for (const f of ['manifest.webmanifest', 'sw.js', 'icone-192.png', 'icone-512.png', 'icone-512-m.png']) {
  let dados;
  if (existsSync(f)) dados = readFileSync(f);
  else {
    const r = await fetch(`https://raw.githubusercontent.com/${REPO}/${versaoEst}/${f}`);
    if (!r.ok) throw new Error(`não deu para baixar ${f} (${r.status})`);
    dados = Buffer.from(await r.arrayBuffer());
  }
  writeFileSync('public/' + f, dados);
}
console.log('public/index.html pronto:', html.length, 'caracteres');
