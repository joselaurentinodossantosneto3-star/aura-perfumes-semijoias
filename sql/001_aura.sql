-- ============================================================================
-- Aura · Perfumes e Semijoias — banco da loja
--
-- Desenho: todas as tabelas ficam no schema privado "aura", que a API não expõe.
-- O site e o painel só falam com o banco pelas funções public.aura_* abaixo.
-- Cada função confere quem está chamando (visitante, cliente com conta ou
-- equipe com sessão) e só então lê ou grava.
-- ============================================================================

create schema if not exists aura;
revoke all on schema aura from public;
revoke all on schema aura from anon, authenticated;

create sequence aura.seq;

-- registros do sistema (peças, clientes, vendas, pedidos, caixa…), um por linha
create table aura.reg (
  colecao       text        not null,
  id            text        not null,
  valor         jsonb       not null,
  seq           bigint      not null default nextval('aura.seq'),   -- sobe a cada mudança (sincronização)
  ordem         bigint      not null default nextval('aura.seq'),   -- ordem de criação (não muda)
  apagado       boolean     not null default false,
  atualizado_em timestamptz not null default now(),
  por           text,
  primary key (colecao, id)
);
create index reg_seq on aura.reg (seq);

-- equipe do painel (a senha fica só como bcrypt)
create table aura.equipe (
  id            text primary key,
  nome          text        not null,
  login         text        not null,
  senha_hash    text        not null,
  papel         text        not null default 'equipe' check (papel in ('dona', 'equipe')),
  ativo         boolean     not null default true,
  vende         boolean     not null default true,
  criado_em     timestamptz not null default now(),
  ultimo_acesso timestamptz
);
create unique index equipe_login on aura.equipe (lower(login));

-- contas de clientes da loja (perfil próprio, separado do cadastro interno de clientes)
create table aura.conta (
  id         text primary key,
  nome       text        not null,
  tel        text        not null unique,       -- só dígitos, sem 55
  email      text        not null default '',
  senha_hash text        not null,
  criado_em  timestamptz not null default now()
);
create unique index conta_email on aura.conta (lower(email)) where email <> '';

-- sessões (painel e conta de cliente); do token só se guarda o resumo
create table aura.sessao (
  token_hash text primary key,
  tipo       text        not null check (tipo in ('painel', 'conta')),
  ref        text        not null,
  criado_em  timestamptz not null default now(),
  expira_em  timestamptz not null
);
create index sessao_expira on aura.sessao (expira_em);

-- contagem para limitar tentativas (senha errada, pedidos em excesso…)
create table aura.tentativa (
  chave  text        not null,
  quando timestamptz not null default now()
);
create index tentativa_chave on aura.tentativa (chave, quando);

-- fotos das peças
create table aura.foto (
  id        text primary key,
  mime      text        not null,
  dados     bytea       not null,
  criado_em timestamptz not null default now(),
  por       text
);

alter table aura.reg       enable row level security;
alter table aura.equipe    enable row level security;
alter table aura.conta     enable row level security;
alter table aura.sessao    enable row level security;
alter table aura.tentativa enable row level security;
alter table aura.foto      enable row level security;
revoke all on all tables    in schema aura from public, anon, authenticated;
revoke all on all sequences in schema aura from public, anon, authenticated;

-- ============================================================================
-- funções internas (schema aura: ninguém de fora chama)
-- ============================================================================

create function aura.iso(t timestamptz default now()) returns text
language sql stable set search_path = '' as $$
  select to_char(t at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
$$;

create function aura.digitos(t text) returns text
language sql immutable set search_path = '' as $$
  select regexp_replace(coalesce(t, ''), '\D', '', 'g')
$$;

-- telefone só com dígitos, sem o 55 do país
create function aura.tel(t text) returns text
language sql immutable set search_path = '' as $$
  select case when length(d) > 11 and left(d, 2) = '55' then substr(d, 3) else d end
  from (select regexp_replace(coalesce(t, ''), '\D', '', 'g') as d) x
$$;
create index reg_cliente_tel on aura.reg (aura.tel(valor ->> 'telefone')) where colecao = 'clientes';
create index reg_pedido_conta on aura.reg ((valor ->> 'contaId')) where colecao = 'pedidos';

create function aura.fone(t text) returns text
language sql immutable set search_path = '' as $$
  select case
    when length(d) = 11 then '(' || substr(d, 1, 2) || ') ' || substr(d, 3, 5) || '-' || substr(d, 8)
    when length(d) = 10 then '(' || substr(d, 1, 2) || ') ' || substr(d, 3, 4) || '-' || substr(d, 7)
    else coalesce(t, '') end
  from (select aura.tel(t) as d) x
$$;

create function aura.txt(t text, n int) returns text
language sql immutable set search_path = '' as $$
  select left(btrim(regexp_replace(coalesce(t, ''), '[[:cntrl:]]+', ' ', 'g')), n)
$$;

create function aura.variante_nome(v jsonb) returns text
language sql immutable set search_path = '' as $$
  select coalesce(v ->> 'acabamento', '') ||
         case when coalesce(v ->> 'tamanho', '') not in ('', 'Único') then ' · ' || (v ->> 'tamanho') else '' end
$$;

create function aura.ip() returns text
language plpgsql stable set search_path = '' as $$
declare h json; v text;
begin
  begin
    h := nullif(current_setting('request.headers', true), '')::json;
  exception when others then h := null;
  end;
  if h is null then return 'local'; end if;
  v := coalesce(nullif(h ->> 'cf-connecting-ip', ''), nullif(h ->> 'x-real-ip', ''),
                nullif(btrim(split_part(coalesce(h ->> 'x-forwarded-for', ''), ',', 1)), ''));
  return coalesce(left(v, 60), 'local');
end $$;

-- conta e registra: devolve false quando passou do limite na janela
create function aura.limite(p_chave text, p_max int, p_janela interval) returns boolean
language plpgsql volatile set search_path = '' as $$
declare n int;
begin
  delete from aura.tentativa where quando < now() - interval '2 days';
  select count(*) into n from aura.tentativa where chave = p_chave and quando > now() - p_janela;
  if n >= p_max then return false; end if;
  insert into aura.tentativa (chave) values (p_chave);
  return true;
end $$;

create function aura.falhas(p_chave text, p_janela interval) returns int
language sql stable set search_path = '' as $$
  select count(*)::int from aura.tentativa where chave = p_chave and quando > now() - p_janela
$$;

create function aura.abrir_sessao(p_tipo text, p_ref text, p_dias int) returns text
language plpgsql volatile set search_path = '' as $$
declare t text := encode(extensions.gen_random_bytes(32), 'hex');
begin
  delete from aura.sessao where expira_em < now();
  insert into aura.sessao (token_hash, tipo, ref, expira_em)
  values (encode(extensions.digest(t, 'sha256'), 'hex'), p_tipo, p_ref, now() + make_interval(days => p_dias));
  return t;
end $$;

create function aura.ler_sessao(p_tipo text, p_token text) returns text
language sql stable set search_path = '' as $$
  select ref from aura.sessao
  where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
    and tipo = p_tipo and expira_em > now()
$$;

create function aura.equipe_json(e aura.equipe) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('id', e.id, 'nome', e.nome, 'login', e.login, 'papel', e.papel, 'ativo', e.ativo, 'vende', e.vende,
    'criadoEm', aura.iso(e.criado_em), 'ultimoAcesso', case when e.ultimo_acesso is null then null else aura.iso(e.ultimo_acesso) end)
$$;

create function aura.config() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce((select valor from aura.reg where colecao = '_' and id = 'config' and not apagado), '{}'::jsonb)
$$;

create function aura.cupom(p_codigo text) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object('codigo', upper(btrim(c ->> 'codigo')),
           'percentual', greatest(0, least(90, coalesce(nullif(c ->> 'percentual', '')::numeric, 0))))
  from jsonb_array_elements(case when jsonb_typeof(aura.config() -> 'cupons') = 'array' then aura.config() -> 'cupons' else '[]'::jsonb end) c
  where btrim(coalesce(p_codigo, '')) <> ''
    and upper(btrim(c ->> 'codigo')) = upper(btrim(p_codigo))
    and coalesce(c ->> 'ativo', 'true') <> 'false'
  limit 1
$$;

create function aura.conta_json(c aura.conta) returns jsonb
language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'cliente', jsonb_build_object('id', c.id, 'nome', c.nome, 'telefone', aura.fone(c.tel), 'email', c.email,
                                  'cpf', '', 'nascimento', '', 'bairro', '', 'cidade', '', 'obs', '', 'origem', 'site',
                                  'criadoEm', aura.iso(c.criado_em), 'ultimaCompra', null, 'senhaSite', true),
    'pedidos', coalesce((select jsonb_agg(valor order by ordem desc) from aura.reg
                         where colecao = 'pedidos' and not apagado and valor ->> 'contaId' = c.id), '[]'::jsonb))
$$;

revoke all on all functions in schema aura from public, anon, authenticated;

-- ============================================================================
-- LOJA (qualquer visitante)
-- ============================================================================

-- o que a vitrine mostra: configurações públicas, categorias e peças à venda (sem custo)
create function public.aura_vitrine() returns jsonb
language sql stable security definer set search_path = '' as $$
  with cfg as (select aura.config() as v)
  select jsonb_build_object(
    'config', (select case when v = '{}'::jsonb then null else (v - 'cupons') || jsonb_build_object('cupons', coalesce((
                 select jsonb_agg(jsonb_build_object('codigo', c ->> 'codigo', 'percentual', c -> 'percentual', 'ativo', true))
                 from jsonb_array_elements(case when jsonb_typeof(v -> 'cupons') = 'array' then v -> 'cupons' else '[]'::jsonb end) c
                 where upper(c ->> 'codigo') = upper(coalesce(v -> 'recuperacao' ->> 'cupom', ''))
                   and coalesce(c ->> 'ativo', 'true') <> 'false'), '[]'::jsonb)) end
               from cfg),
    'categorias', (select valor from aura.reg where colecao = '_' and id = 'categorias' and not apagado),
    'ocasioes',   (select valor from aura.reg where colecao = '_' and id = 'ocasioes' and not apagado),
    'produtos', coalesce((select jsonb_agg(valor - 'custo' order by ordem) from aura.reg
                          where colecao = 'produtos' and not apagado
                            and coalesce(valor ->> 'ativo', 'false') = 'true'
                            and coalesce(valor ->> 'arquivado', 'false') <> 'true'), '[]'::jsonb))
$$;

create function public.aura_cupom(p_codigo text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  if not aura.limite('cupom:' || aura.ip(), 30, interval '10 minutes') then return null; end if;
  return aura.cupom(p_codigo);
end $$;

create function public.aura_foto(p_id text) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('mime', mime, 'b64', replace(encode(dados, 'base64'), E'\n', ''))
  from aura.foto where id = p_id
$$;

-- sacola de quem começou o checkout (para a loja poder chamar de volta)
create function public.aura_carrinho(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare tok text; it jsonb; pr jsonb; va jsonb; q int; itens jsonb := '[]'::jsonb; sub numeric := 0; n int := 0;
        atual jsonb; cid text; agora text := aura.iso(); novo jsonb;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false); end if;
  tok := p ->> 'token';
  if tok is null or length(tok) < 8 or length(tok) > 80 then return jsonb_build_object('ok', false); end if;
  if not aura.limite('carrinho:' || aura.ip(), 240, interval '1 hour') then return jsonb_build_object('ok', false); end if;
  if jsonb_typeof(p -> 'itens') = 'array' then
    for it in select * from jsonb_array_elements(p -> 'itens') loop
      n := n + 1; exit when n > 60;
      select valor into pr from aura.reg where colecao = 'produtos' and id = it ->> 'produtoId' and not apagado;
      continue when pr is null;
      select v into va from jsonb_array_elements(pr -> 'variantes') v where v ->> 'id' = it ->> 'varianteId' limit 1;
      continue when va is null;
      begin q := greatest(1, least(99, floor((it ->> 'qtd')::numeric)::int)); exception when others then q := 1; end;
      itens := itens || jsonb_build_object('produtoId', pr ->> 'id', 'varianteId', va ->> 'id', 'nome', pr ->> 'nome',
                 'variacao', aura.variante_nome(va), 'qtd', q, 'preco', round((pr ->> 'preco')::numeric, 2));
      sub := sub + round((pr ->> 'preco')::numeric, 2) * q;
    end loop;
  end if;
  if jsonb_array_length(itens) = 0 then return jsonb_build_object('ok', false); end if;
  perform pg_advisory_xact_lock(771001);
  select id, valor into cid, atual from aura.reg where colecao = 'carrinhos' and valor ->> 'token' = tok limit 1;
  if cid is null then
    cid := 'ca-' || encode(extensions.gen_random_bytes(8), 'hex');
    atual := jsonb_build_object('id', cid, 'token', tok, 'criadoEm', agora, 'motivo', '', 'contatadoEm', null, 'concluidoEm', null, 'ignorado', false);
  end if;
  novo := atual || jsonb_build_object('nome', aura.txt(p ->> 'nome', 80), 'telefone', aura.fone(aura.txt(p ->> 'telefone', 30)),
            'email', aura.txt(p ->> 'email', 120), 'itens', itens, 'subtotal', round(sub, 2), 'atualizadoEm', agora);
  if p ? 'motivo' then novo := novo || jsonb_build_object('motivo', aura.txt(p ->> 'motivo', 80)); end if;
  insert into aura.reg (colecao, id, valor, por) values ('carrinhos', cid, novo, 'site')
  on conflict (colecao, id) do update set valor = excluded.valor, apagado = false, seq = nextval('aura.seq'), atualizado_em = now(), por = 'site';
  return jsonb_build_object('ok', true);
end $$;

-- pedido do site: tudo é recalculado aqui com os preços do banco
create function public.aura_pedido(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare
  cfg jsonb := aura.config(); nome text; tel text; email text; it jsonb; pr jsonb; va jsonb; q int; preco numeric;
  itens jsonb := '[]'::jsonb; sub numeric := 0; cup jsonb; descv numeric := 0; ent jsonb; frete numeric; pag text;
  pixpct numeric; descpix numeric := 0; base numeric; total numeric; pid text; ref text; agora text := aura.iso();
  cli_id text; endr jsonb; e jsonb; conta_id text; pd jsonb; n int := 0; tok text; obrig boolean;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'Pedido inválido.'); end if;
  if not aura.limite('pedido:' || aura.ip(), 12, interval '1 hour') then
    return jsonb_build_object('ok', false, 'erro', 'Muitos pedidos em pouco tempo. Tente de novo mais tarde ou chame a loja no WhatsApp.');
  end if;
  nome := aura.txt(p -> 'cliente' ->> 'nome', 80);
  tel := aura.tel(p -> 'cliente' ->> 'telefone');
  email := aura.txt(p -> 'cliente' ->> 'email', 120);
  if length(nome) < 2 then return jsonb_build_object('ok', false, 'erro', 'Informe seu nome.'); end if;
  if length(tel) < 10 or length(tel) > 11 then return jsonb_build_object('ok', false, 'erro', 'Informe o WhatsApp com DDD.'); end if;
  if jsonb_typeof(p -> 'itens') <> 'array' then return jsonb_build_object('ok', false, 'erro', 'A sacola está vazia.'); end if;

  for it in select * from jsonb_array_elements(p -> 'itens') loop
    n := n + 1; exit when n > 60;
    select valor into pr from aura.reg where colecao = 'produtos' and id = it ->> 'produtoId' and not apagado
      and coalesce(valor ->> 'ativo', 'false') = 'true' and coalesce(valor ->> 'arquivado', 'false') <> 'true';
    if pr is null then return jsonb_build_object('ok', false, 'erro', 'Uma peça da sacola não está mais disponível. Atualize a página e confira a sacola.'); end if;
    select v into va from jsonb_array_elements(pr -> 'variantes') v where v ->> 'id' = it ->> 'varianteId' limit 1;
    if va is null then return jsonb_build_object('ok', false, 'erro', 'Uma opção da sacola não está mais disponível. Atualize a página e confira a sacola.'); end if;
    begin q := greatest(1, least(99, floor((it ->> 'qtd')::numeric)::int)); exception when others then q := 1; end;
    preco := round((pr ->> 'preco')::numeric, 2);
    itens := itens || jsonb_build_object('produtoId', pr ->> 'id', 'varianteId', va ->> 'id', 'nome', pr ->> 'nome',
               'variacao', aura.variante_nome(va), 'qtd', q, 'preco', preco);
    sub := sub + preco * q;
  end loop;
  if jsonb_array_length(itens) = 0 then return jsonb_build_object('ok', false, 'erro', 'A sacola está vazia.'); end if;
  sub := round(sub, 2);

  cup := aura.cupom(p ->> 'cupom');
  if cup is not null then descv := round(sub * (cup ->> 'percentual')::numeric / 100, 2); end if;

  if jsonb_typeof(cfg -> 'entrega') = 'array' then
    select x into ent from jsonb_array_elements(cfg -> 'entrega') x where x ->> 'id' = p ->> 'entregaId' limit 1;
    if ent is null then ent := cfg -> 'entrega' -> 0; end if;
  end if;
  if ent is null then ent := jsonb_build_object('id', 'combinar', 'label', 'A combinar', 'valor', null); end if;
  frete := case when jsonb_typeof(ent -> 'valor') = 'number' then round((ent ->> 'valor')::numeric, 2) else null end;
  obrig := coalesce(ent ->> 'enderecoObrigatorio', 'false') = 'true';
  if obrig then
    e := p -> 'endereco';
    if e is null or jsonb_typeof(e) <> 'object' or length(aura.digitos(e ->> 'cep')) <> 8 or aura.txt(e ->> 'rua', 120) = ''
       or aura.txt(e ->> 'numero', 20) = '' or aura.txt(e ->> 'bairro', 80) = '' or aura.txt(e ->> 'cidade', 80) = '' or length(aura.txt(e ->> 'uf', 2)) <> 2 then
      return jsonb_build_object('ok', false, 'erro', 'Confira o endereço de entrega.');
    end if;
    endr := jsonb_build_object('cep', aura.txt(e ->> 'cep', 9), 'rua', aura.txt(e ->> 'rua', 120), 'numero', aura.txt(e ->> 'numero', 20),
              'complemento', aura.txt(e ->> 'complemento', 80), 'bairro', aura.txt(e ->> 'bairro', 80), 'cidade', aura.txt(e ->> 'cidade', 80),
              'uf', upper(aura.txt(e ->> 'uf', 2)));
  end if;

  -- pagamento: Pix pela chave da loja (com o desconto do Pix) ou combinar pelo WhatsApp
  pag := case when p ->> 'pagamento' = 'pix' and btrim(coalesce(cfg -> 'pagamento' ->> 'pixChave', '')) <> '' then 'pix' else 'whatsapp' end;
  if pag = 'pix' then
    pixpct := coalesce(nullif(cfg -> 'pagamento' ->> 'descontoPix', '')::numeric, 0);
    if pixpct > 0 and pixpct < 100 then
      base := sub - descv;
      descpix := round(base - round(base * (1 - pixpct / 100), 2), 2);
    end if;
  end if;
  total := round(sub - descv - descpix + coalesce(frete, 0), 2);

  conta_id := aura.ler_sessao('conta', p ->> 'conta');
  tok := nullif(aura.txt(p ->> 'carrinhoToken', 80), '');

  perform pg_advisory_xact_lock(771001);
  select id into cli_id from aura.reg where colecao = 'clientes' and not apagado and aura.tel(valor ->> 'telefone') = tel limit 1;
  if cli_id is null then
    cli_id := 'cl-' || encode(extensions.gen_random_bytes(8), 'hex');
    insert into aura.reg (colecao, id, valor, por) values ('clientes', cli_id, jsonb_build_object(
      'id', cli_id, 'nome', nome, 'telefone', aura.fone(tel), 'email', email, 'cpf', '', 'nascimento', '',
      'bairro', coalesce(endr ->> 'bairro', ''), 'cidade', coalesce(endr ->> 'cidade', ''), 'obs', '',
      'criadoEm', agora, 'origem', 'site', 'ultimaCompra', null), 'site');
  end if;
  pid := 'pd-' || encode(extensions.gen_random_bytes(8), 'hex');
  loop
    ref := 'AU-' || upper(substr(encode(extensions.gen_random_bytes(5), 'hex'), 1, 7));
    exit when not exists (select 1 from aura.reg where colecao = 'pedidos' and valor ->> 'ref' = ref);
  end loop;
  pd := jsonb_build_object('id', pid, 'ref', ref, 'data', agora,
    'cliente', jsonb_build_object('nome', nome, 'telefone', aura.fone(tel), 'email', email),
    'itens', itens, 'subtotal', sub, 'cupom', cup, 'desconto', descv,
    'entrega', jsonb_build_object('id', ent ->> 'id', 'label', ent ->> 'label', 'valor', frete),
    'endereco', endr, 'pagamento', pag, 'forma', case when pag = 'pix' then 'pix' else null end, 'parcelas', null,
    'descontoPix', descpix, 'obs', aura.txt(p ->> 'obs', 400), 'total', total, 'freteACombinar', frete is null,
    'status', 'novo', 'vendaId', null, 'carrinhoToken', tok,
    'historico', jsonb_build_array(jsonb_build_object('status', 'novo', 'data', agora, 'usuarioId', null)),
    'clienteId', cli_id, 'contaId', conta_id);
  insert into aura.reg (colecao, id, valor, por) values ('pedidos', pid, pd, 'site');
  if tok is not null then
    update aura.reg set valor = valor || jsonb_build_object('concluidoEm', agora), seq = nextval('aura.seq'), atualizado_em = now()
    where colecao = 'carrinhos' and valor ->> 'token' = tok and coalesce(valor ->> 'concluidoEm', '') = '';
  end if;
  return jsonb_build_object('ok', true, 'pedido', pd);
end $$;

-- ---------------------------------------------------------------------------
-- conta de cliente
-- ---------------------------------------------------------------------------
create function public.aura_conta_criar(p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare v_nome text; v_tel text; v_email text; v_senha text; c aura.conta; cid text;
begin
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'Dados inválidos.'); end if;
  if not aura.limite('conta-nova:' || aura.ip(), 10, interval '1 hour') then
    return jsonb_build_object('ok', false, 'erro', 'Muitas tentativas. Tente de novo mais tarde.');
  end if;
  v_nome := aura.txt(p ->> 'nome', 80); v_tel := aura.tel(p ->> 'telefone'); v_email := lower(aura.txt(p ->> 'email', 120)); v_senha := coalesce(p ->> 'senha', '');
  if length(v_nome) < 2 then return jsonb_build_object('ok', false, 'erro', 'Informe seu nome.', 'campo', 'nome'); end if;
  if length(v_tel) < 10 or length(v_tel) > 11 then return jsonb_build_object('ok', false, 'erro', 'Informe o WhatsApp com DDD.', 'campo', 'telefone'); end if;
  if v_email <> '' and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'erro', 'Confira o e-mail.', 'campo', 'email'); end if;
  if length(v_senha) < 6 or length(v_senha) > 72 then return jsonb_build_object('ok', false, 'erro', 'A senha precisa ter pelo menos 6 caracteres.', 'campo', 'senha'); end if;
  if exists (select 1 from aura.conta x where x.tel = v_tel) then
    return jsonb_build_object('ok', false, 'erro', 'Já existe uma conta com esse WhatsApp. Entre com a sua senha.', 'campo', 'telefone');
  end if;
  if v_email <> '' and exists (select 1 from aura.conta x where lower(x.email) = v_email) then
    return jsonb_build_object('ok', false, 'erro', 'Já existe uma conta com esse e-mail. Tente entrar.', 'campo', 'email');
  end if;
  cid := 'ct-' || encode(extensions.gen_random_bytes(8), 'hex');
  insert into aura.conta (id, nome, tel, email, senha_hash)
  values (cid, v_nome, v_tel, v_email, extensions.crypt(v_senha, extensions.gen_salt('bf', 10))) returning * into c;
  return jsonb_build_object('ok', true, 'token', aura.abrir_sessao('conta', c.id, 90)) || aura.conta_json(c);
end $$;

create function public.aura_conta_entrar(p_login text, p_senha text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare l text := lower(btrim(coalesce(p_login, ''))); c aura.conta; v_chave text; ip text := aura.ip();
begin
  if l = '' or coalesce(p_senha, '') = '' then return jsonb_build_object('ok', false, 'erro', 'credenciais'); end if;
  v_chave := 'conta:' || left(case when position('@' in l) > 0 then l else aura.tel(l) end, 120);
  if aura.falhas(v_chave, interval '15 minutes') >= 8 or aura.falhas('conta-ip:' || ip, interval '15 minutes') >= 40 then
    return jsonb_build_object('ok', false, 'erro', 'bloqueado');
  end if;
  if position('@' in l) > 0 then select * into c from aura.conta x where lower(x.email) = l and x.email <> '';
  else select * into c from aura.conta x where x.tel = aura.tel(l);
  end if;
  if c.id is null or extensions.crypt(p_senha, c.senha_hash) <> c.senha_hash then
    if c.id is null then perform extensions.crypt(p_senha, '$2a$10$CliLjN5MRVZ5gip7DpCT6.OXWStxRMp/oDd0WpWi.dWRO86LyU7YS'); end if;
    insert into aura.tentativa (chave) values (v_chave), ('conta-ip:' || ip);
    return jsonb_build_object('ok', false, 'erro', 'credenciais');
  end if;
  delete from aura.tentativa t where t.chave = v_chave;
  return jsonb_build_object('ok', true, 'token', aura.abrir_sessao('conta', c.id, 90)) || aura.conta_json(c);
end $$;

create function public.aura_conta_eu(p_token text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare c aura.conta;
begin
  select * into c from aura.conta where id = aura.ler_sessao('conta', p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
  return jsonb_build_object('ok', true) || aura.conta_json(c);
end $$;

create function public.aura_conta_salvar(p_token text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare c aura.conta; v_nome text; v_tel text; v_email text;
begin
  select * into c from aura.conta where id = aura.ler_sessao('conta', p_token);
  if c.id is null then return jsonb_build_object('ok', false, 'erro', 'Entre de novo na sua conta.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'Dados inválidos.'); end if;
  v_nome := aura.txt(p ->> 'nome', 80); v_tel := aura.tel(p ->> 'telefone');
  v_email := case when p ? 'email' then lower(aura.txt(p ->> 'email', 120)) else c.email end;
  if length(v_nome) < 2 then return jsonb_build_object('ok', false, 'erro', 'Informe seu nome.'); end if;
  if length(v_tel) < 10 or length(v_tel) > 11 then return jsonb_build_object('ok', false, 'erro', 'Informe o WhatsApp com DDD.'); end if;
  if v_email <> '' and v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then return jsonb_build_object('ok', false, 'erro', 'Confira o e-mail.'); end if;
  if exists (select 1 from aura.conta x where x.tel = v_tel and x.id <> c.id) then
    return jsonb_build_object('ok', false, 'erro', 'Já existe uma conta com esse WhatsApp.');
  end if;
  if v_email <> '' and exists (select 1 from aura.conta x where lower(x.email) = v_email and x.id <> c.id) then
    return jsonb_build_object('ok', false, 'erro', 'Já existe uma conta com esse e-mail.');
  end if;
  update aura.conta x set nome = v_nome, tel = v_tel, email = v_email where x.id = c.id returning x.* into c;
  return jsonb_build_object('ok', true) || aura.conta_json(c);
end $$;

-- ============================================================================
-- PAINEL (equipe com sessão)
-- ============================================================================

create function public.aura_entrar(p_login text, p_senha text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare l text := lower(btrim(coalesce(p_login, ''))); e aura.equipe; ip text := aura.ip();
begin
  if l = '' or coalesce(p_senha, '') = '' or length(l) > 120 then return jsonb_build_object('ok', false, 'erro', 'credenciais'); end if;
  if aura.falhas('login:' || l, interval '15 minutes') >= 8 or aura.falhas('login-ip:' || ip, interval '15 minutes') >= 40 then
    return jsonb_build_object('ok', false, 'erro', 'bloqueado');
  end if;
  select * into e from aura.equipe where lower(login) = l and ativo;
  if e.id is null or extensions.crypt(p_senha, e.senha_hash) <> e.senha_hash then
    if e.id is null then perform extensions.crypt(p_senha, '$2a$10$CliLjN5MRVZ5gip7DpCT6.OXWStxRMp/oDd0WpWi.dWRO86LyU7YS'); end if;
    insert into aura.tentativa (chave) values ('login:' || l), ('login-ip:' || ip);
    return jsonb_build_object('ok', false, 'erro', 'credenciais');
  end if;
  delete from aura.tentativa where chave = 'login:' || l;
  update aura.equipe set ultimo_acesso = now() where id = e.id returning * into e;
  return jsonb_build_object('ok', true, 'token', aura.abrir_sessao('painel', e.id, 7), 'usuario', aura.equipe_json(e));
end $$;

create function public.aura_sair(p_token text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
begin
  delete from aura.sessao where token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
  return jsonb_build_object('ok', true);
end $$;

-- grava o que mudou neste aparelho e devolve o que mudou no banco desde p_desde
create function public.aura_sincronizar(p_token text, p_desde bigint default 0, p_mudancas jsonb default '[]'::jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare e aura.equipe; m jsonb; c text; i text; v jsonb; dona boolean; topo bigint; regs jsonb; n int := 0; antes jsonb; k text;
begin
  select * into e from aura.equipe where id = aura.ler_sessao('painel', p_token) and ativo;
  if e.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
  dona := e.papel = 'dona';
  if jsonb_typeof(p_mudancas) = 'array' and jsonb_array_length(p_mudancas) > 0 then
    perform pg_advisory_xact_lock(771001);
    for m in select * from jsonb_array_elements(p_mudancas) loop
      n := n + 1; exit when n > 5000;
      c := m ->> 'c'; i := m ->> 'id'; v := m -> 'v';
      continue when c is null or i is null or length(i) > 120 or i = '';
      continue when c not in ('produtos', 'clientes', 'vendas', 'caixa', 'cashback', 'fluxo', 'movs', 'pedidos', 'carrinhos', '_');
      continue when c = '_' and i not in ('config', 'categorias', 'ocasioes', 'cashbackRegras', 'equipeRegras', 'contadores');
      continue when c = '_' and i <> 'contadores' and not dona;
      if v is null or jsonb_typeof(v) = 'null' then
        update aura.reg set apagado = true, seq = nextval('aura.seq'), atualizado_em = now(), por = e.id
        where colecao = c and id = i and not apagado;
      else
        if c = '_' and i = 'contadores' and jsonb_typeof(v) = 'object' then   -- numeração nunca volta para trás
          select valor into antes from aura.reg where colecao = '_' and id = 'contadores';
          if antes is not null and jsonb_typeof(antes) = 'object' then
            for k in select jsonb_object_keys(antes) loop
              if jsonb_typeof(antes -> k) = 'number' and (not (v ? k) or jsonb_typeof(v -> k) <> 'number' or (v ->> k)::numeric < (antes ->> k)::numeric) then
                v := v || jsonb_build_object(k, antes -> k);
              end if;
            end loop;
          end if;
        end if;
        insert into aura.reg as r (colecao, id, valor, por) values (c, i, v, e.id)
        on conflict (colecao, id) do update
          set valor = excluded.valor, apagado = false, seq = nextval('aura.seq'), atualizado_em = now(), por = excluded.por
          where r.valor is distinct from excluded.valor or r.apagado;
      end if;
    end loop;
  end if;
  select coalesce(max(seq), 0) into topo from aura.reg;
  select coalesce(jsonb_agg(jsonb_build_object('c', colecao, 'id', id, 'v', case when apagado then null else valor end, 'a', apagado, 'o', ordem) order by ordem), '[]'::jsonb)
    into regs
  from aura.reg
  where seq > coalesce(p_desde, 0) and seq <= topo
    and (coalesce(p_desde, 0) > 0 or not apagado)
    and (dona or colecao <> 'caixa');
  return jsonb_build_object('ok', true, 'seq', topo, 'registros', regs, 'eu', aura.equipe_json(e),
    'equipe', (select coalesce(jsonb_agg(aura.equipe_json(x) order by x.criado_em), '[]'::jsonb) from aura.equipe x));
end $$;

-- a dona cadastra ou altera alguém da equipe (e pode definir a senha)
create function public.aura_equipe_salvar(p_token text, p jsonb) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare eu aura.equipe; alvo aura.equipe; uid text; v_nome text; lg text; v_papel text; v_ativo boolean; v_vende boolean; v_senha text; donas int;
begin
  select * into eu from aura.equipe x where x.id = aura.ler_sessao('painel', p_token) and x.ativo;
  if eu.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
  if eu.papel <> 'dona' then return jsonb_build_object('ok', false, 'erro', 'Só a dona da loja altera a equipe.'); end if;
  if p is null or jsonb_typeof(p) <> 'object' then return jsonb_build_object('ok', false, 'erro', 'Dados inválidos.'); end if;
  uid := aura.txt(p ->> 'id', 60); v_nome := aura.txt(p ->> 'nome', 60); lg := lower(aura.txt(p ->> 'login', 60));
  v_papel := case when p ->> 'papel' = 'dona' then 'dona' else 'equipe' end;
  v_ativo := coalesce(p ->> 'ativo', 'true') <> 'false'; v_vende := coalesce(p ->> 'vende', 'true') <> 'false';
  v_senha := p ->> 'senha';
  if uid = '' then return jsonb_build_object('ok', false, 'erro', 'Dados inválidos.'); end if;
  if length(v_nome) < 1 then return jsonb_build_object('ok', false, 'erro', 'Informe o nome.'); end if;
  if lg !~ '^[a-z0-9._@+-]{3,60}$' then return jsonb_build_object('ok', false, 'erro', 'Use de 3 a 60 caracteres no usuário, sem espaço.'); end if;
  if exists (select 1 from aura.equipe x where lower(x.login) = lg and x.id <> uid) then return jsonb_build_object('ok', false, 'erro', 'Esse usuário já existe. Escolha outro.'); end if;
  if v_senha is not null and (length(v_senha) < 6 or length(v_senha) > 72) then return jsonb_build_object('ok', false, 'erro', 'A senha precisa de pelo menos 6 caracteres.'); end if;
  select * into alvo from aura.equipe x where x.id = uid;
  if alvo.id is null then
    if v_senha is null then return jsonb_build_object('ok', false, 'erro', 'Defina uma senha para a pessoa nova.'); end if;
    insert into aura.equipe (id, nome, login, senha_hash, papel, ativo, vende)
    values (uid, v_nome, lg, extensions.crypt(v_senha, extensions.gen_salt('bf', 10)), v_papel, true, v_vende);
  else
    select count(*) into donas from aura.equipe x where x.papel = 'dona' and x.ativo and x.id <> alvo.id;
    if alvo.papel = 'dona' and alvo.ativo and donas = 0 and (v_papel <> 'dona' or not v_ativo) then
      return jsonb_build_object('ok', false, 'erro', 'A loja precisa de pelo menos uma dona ativa.');
    end if;
    if alvo.id = eu.id and (v_papel <> 'dona' or not v_ativo) then return jsonb_build_object('ok', false, 'erro', 'Você não pode tirar o seu próprio acesso.'); end if;
    if alvo.id = eu.id and v_senha is not null then return jsonb_build_object('ok', false, 'erro', 'Troque a sua senha em Minha conta.'); end if;
    update aura.equipe x set nome = v_nome, login = lg, papel = v_papel, ativo = v_ativo, vende = v_vende,
      senha_hash = case when v_senha is null then x.senha_hash else extensions.crypt(v_senha, extensions.gen_salt('bf', 10)) end
    where x.id = alvo.id;
    if v_senha is not null or not v_ativo then delete from aura.sessao where tipo = 'painel' and ref = alvo.id; end if;
  end if;
  return jsonb_build_object('ok', true,
    'equipe', (select coalesce(jsonb_agg(aura.equipe_json(x) order by x.criado_em), '[]'::jsonb) from aura.equipe x));
end $$;

-- cada pessoa troca a própria senha (precisa da atual)
create function public.aura_senha_trocar(p_token text, p_atual text, p_nova text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare eu aura.equipe; th text := encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex');
begin
  select * into eu from aura.equipe where id = aura.ler_sessao('painel', p_token) and ativo;
  if eu.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
  if aura.falhas('senha:' || eu.id, interval '15 minutes') >= 8 then return jsonb_build_object('ok', false, 'erro', 'Muitas tentativas. Espere alguns minutos.'); end if;
  if extensions.crypt(coalesce(p_atual, ''), eu.senha_hash) <> eu.senha_hash then
    insert into aura.tentativa (chave) values ('senha:' || eu.id);
    return jsonb_build_object('ok', false, 'erro', 'A senha atual não confere.');
  end if;
  if length(coalesce(p_nova, '')) < 6 or length(p_nova) > 72 then return jsonb_build_object('ok', false, 'erro', 'A nova senha precisa de pelo menos 6 caracteres.'); end if;
  update aura.equipe set senha_hash = extensions.crypt(p_nova, extensions.gen_salt('bf', 10)) where id = eu.id;
  delete from aura.sessao where tipo = 'painel' and ref = eu.id and token_hash <> th;
  return jsonb_build_object('ok', true);
end $$;

create function public.aura_foto_salvar(p_token text, p_mime text, p_b64 text) returns jsonb
language plpgsql volatile security definer set search_path = '' as $$
declare eu aura.equipe; b bytea; fid text;
begin
  select * into eu from aura.equipe where id = aura.ler_sessao('painel', p_token) and ativo;
  if eu.id is null then return jsonb_build_object('ok', false, 'erro', 'sessao'); end if;
  if p_mime not in ('image/jpeg', 'image/png', 'image/webp') then return jsonb_build_object('ok', false, 'erro', 'Use uma foto JPG, PNG ou WebP.'); end if;
  begin b := decode(p_b64, 'base64'); exception when others then return jsonb_build_object('ok', false, 'erro', 'Não deu para ler a foto.'); end;
  if length(b) < 100 or length(b) > 900000 then return jsonb_build_object('ok', false, 'erro', 'A foto ficou grande demais. Tente outra.'); end if;
  fid := encode(extensions.gen_random_bytes(10), 'hex');
  insert into aura.foto (id, mime, dados, por) values (fid, p_mime, b, eu.id);
  return jsonb_build_object('ok', true, 'id', fid);
end $$;

-- quem pode chamar o quê
revoke all on all functions in schema public from public;
grant execute on function
  public.aura_vitrine(), public.aura_cupom(text), public.aura_foto(text), public.aura_carrinho(jsonb), public.aura_pedido(jsonb),
  public.aura_conta_criar(jsonb), public.aura_conta_entrar(text, text), public.aura_conta_eu(text), public.aura_conta_salvar(text, jsonb),
  public.aura_entrar(text, text), public.aura_sair(text), public.aura_sincronizar(text, bigint, jsonb),
  public.aura_equipe_salvar(text, jsonb), public.aura_senha_trocar(text, text, text), public.aura_foto_salvar(text, text, text)
to anon, authenticated;
