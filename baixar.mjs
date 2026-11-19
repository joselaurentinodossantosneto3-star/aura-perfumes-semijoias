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
console.log('public/index.html pronto:', html.length, 'caracteres');
