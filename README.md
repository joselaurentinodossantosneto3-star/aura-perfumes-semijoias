# Aura · Perfumes e Semijoias

Loja online e painel da Aura ([@oficial.useaura](https://www.instagram.com/oficial.useaura/)).

- `index.html`: a loja e o painel (página única). O painel fica em `#painel`.
- `api/foto.js`: entrega as fotos das peças em `/foto/<id>.jpg`.
- `sql/001_aura.sql`: o banco (Supabase). As tabelas ficam num schema privado; o site só fala com o banco pelas funções `aura_*`, que conferem quem está chamando.
- `baixar.mjs`, `vercel.json`, `package.json`: publicação na Vercel.

Nada aqui é segredo: a chave que aparece no código é a chave pública do banco. Senhas ficam só no servidor, como bcrypt.
