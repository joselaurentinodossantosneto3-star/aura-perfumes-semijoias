// uso: node render.js preview <saida_dir> t1,t2,...   |   node render.js video <saida.mp4> <fps> <workers>
const { chromium } = require('playwright');
const { spawn } = require('child_process');
const path = require('path'), fs = require('fs');
const PAGE = 'file://' + path.join(__dirname, 'motion.html');
async function abrir(b) {
  const p = await b.newPage({ viewport: { width: 1080, height: 1920 } });
  const errs = []; p.on('pageerror', e => errs.push(e.message)); p.on('console', m => m.type() === 'error' && errs.push(m.text()));
  await p.goto(PAGE); await p.evaluate(() => window.__pronto);
  if (errs.length) console.error('ERROS:', errs);
  return p;
}
(async () => {
  const [mode, out, a3, a4] = process.argv.slice(2);
  const b = await chromium.launch({ args: ['--allow-file-access-from-files', '--disable-web-security'] });
  if (mode === 'preview') {
    const p = await abrir(b);
    for (const t of a3.split(',').map(Number)) {
      const d = await p.evaluate(t => window.__frame(t, .85), t);
      fs.writeFileSync(path.join(out, `m_${t.toFixed(2).padStart(5, '0')}.jpg`), Buffer.from(d.split(',')[1], 'base64'));
    }
    await b.close(); return;
  }
  const fps = +a3, nw = +a4;
  const p0 = await abrir(b); const total = await p0.evaluate(() => window.TOTAL); await p0.close();
  const N = Math.round(total * fps), per = Math.ceil(N / nw);
  const t0 = Date.now();
  await Promise.all([...Array(nw).keys()].map(async w => {
    const p = await abrir(b);
    const ff = spawn('ffmpeg', ['-v', 'error', '-y', '-f', 'image2pipe', '-c:v', 'mjpeg', '-framerate', String(fps), '-i', '-',
      '-c:v', 'libx264', '-preset', 'fast', '-crf', '12', '-pix_fmt', 'yuv420p', `${out}.part${w}.mp4`], { stdio: ['pipe', 'inherit', 'inherit'] });
    for (let f = w * per; f < Math.min(N, (w + 1) * per); f++) {
      const d = await p.evaluate(t => window.__frame(t, .95), f / fps);
      const buf = Buffer.from(d.split(',')[1], 'base64');
      if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
      if (w === 0 && f % 60 === 0) console.error(`quadro ${f}/${per} (${((Date.now() - t0) / 1000).toFixed(0)}s)`);
    }
    ff.stdin.end(); await new Promise(r => ff.on('close', r));
  }));
  fs.writeFileSync(`${out}.list`, [...Array(nw).keys()].map(w => `file '${path.resolve(out)}.part${w}.mp4'`).join('\n'));
  console.error('pronto em', ((Date.now() - t0) / 1000).toFixed(0), 's');
  await b.close();
})();
