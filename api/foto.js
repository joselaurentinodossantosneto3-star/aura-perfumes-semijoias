// Entrega as fotos das peças: /foto/<id>.jpg busca a imagem no banco da Aura e devolve com cache longo.
const BANCO = 'https://rezoytocwddduywrzftc.supabase.co';
const CHAVE = 'sb_publishable_tzyWHW3kHHas4knHga96pA_UtP_Qid-'; // chave pública (a mesma do site)

module.exports = async (req, res) => {
  const id = String((req.query && req.query.id) || '').replace(/\.[a-z0-9]+$/i, '');
  if (!/^[a-f0-9]{8,40}$/.test(id)) { res.statusCode = 400; return res.end('foto inválida'); }
  try {
    const r = await fetch(BANCO + '/rest/v1/rpc/aura_foto', {
      method: 'POST',
      headers: { apikey: CHAVE, Authorization: 'Bearer ' + CHAVE, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_id: id })
    });
    const j = r.ok ? await r.json() : null;
    if (!j || !j.b64) { res.statusCode = 404; res.setHeader('Cache-Control', 'public, max-age=60'); return res.end('foto não encontrada'); }
    res.statusCode = 200;
    res.setHeader('Content-Type', j.mime || 'image/jpeg');
    res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
    res.end(Buffer.from(j.b64, 'base64'));
  } catch (e) {
    res.statusCode = 502; res.end('erro ao buscar a foto');
  }
};
