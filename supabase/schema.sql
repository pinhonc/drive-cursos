-- =====================================================================
-- Academia Drive In — banco no Supabase
-- Rode este arquivo inteiro no SQL Editor do projeto Supabase.
-- Todas as tabelas e funções usam o prefixo "trein_" para não
-- conflitar com outros apps no mesmo projeto.
-- As tabelas ficam fechadas (RLS sem políticas); o site só acessa
-- os dados pelas funções abaixo.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.trein_participantes (
  id         uuid primary key default gen_random_uuid(),
  nome       text not null,
  nome_norm  text not null unique,
  setor      text not null,
  pin_hash   text not null,
  token      uuid not null default gen_random_uuid(),
  criado_em  timestamptz not null default now()
);

create table if not exists public.trein_tentativas (
  id              bigserial primary key,
  participante_id uuid not null references public.trein_participantes(id) on delete cascade,
  curso           text not null,
  acertos         int  not null,
  total           int  not null,
  pontos          int  not null,
  respostas       jsonb not null default '[]'::jsonb,
  criado_em       timestamptz not null default now()
);
create index if not exists trein_tentativas_curso_idx on public.trein_tentativas (curso, pontos desc);

create table if not exists public.trein_config (
  chave text primary key,
  valor text not null
);

alter table public.trein_participantes enable row level security;
alter table public.trein_tentativas    enable row level security;
alter table public.trein_config        enable row level security;

-- Senhas iniciais (troque depois com os comandos do final do arquivo)
-- código da equipe (pedido no cadastro): 1978
-- senha do gestor (Área do gestor):      gestor1978
insert into public.trein_config (chave, valor) values
  ('codigo_equipe', extensions.crypt('1978', extensions.gen_salt('bf'))),
  ('senha_gestor',  extensions.crypt('gestor1978', extensions.gen_salt('bf')))
on conflict (chave) do nothing;

-- ---------------------------------------------------------------------
create or replace function public.trein__norm(p text) returns text
language sql immutable as $$
  select lower(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g'))
$$;

create or replace function public.trein__confere(p_chave text, p_valor text) returns boolean
language plpgsql security definer set search_path = public, extensions as $$
declare v text;
begin
  select valor into v from trein_config where chave = p_chave;
  return v is not null and crypt(coalesce(p_valor, ''), v) = v;
end $$;

-- Cadastro ------------------------------------------------------------
create or replace function public.trein_registrar(p_nome text, p_setor text, p_pin text, p_codigo text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare r trein_participantes;
begin
  if not trein__confere('codigo_equipe', p_codigo) then
    raise exception 'Código da equipe incorreto. Peça o código ao seu gestor.';
  end if;
  if length(trim(coalesce(p_nome, ''))) < 3 then
    raise exception 'Digite seu nome e sobrenome.';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN precisa ter 4 números.';
  end if;
  if exists (select 1 from trein_participantes where nome_norm = trein__norm(p_nome)) then
    raise exception 'Esse nome já está cadastrado. Use a aba Entrar.';
  end if;
  insert into trein_participantes (nome, nome_norm, setor, pin_hash)
  values (regexp_replace(trim(p_nome), '\s+', ' ', 'g'), trein__norm(p_nome), p_setor, crypt(p_pin, gen_salt('bf')))
  returning * into r;
  return json_build_object('id', r.id, 'nome', r.nome, 'setor', r.setor, 'token', r.token);
end $$;

-- Login ---------------------------------------------------------------
create or replace function public.trein_entrar(p_nome text, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare r trein_participantes;
begin
  select * into r from trein_participantes where nome_norm = trein__norm(p_nome);
  if r.id is null or crypt(coalesce(p_pin, ''), r.pin_hash) <> r.pin_hash then
    raise exception 'Nome ou PIN incorretos.';
  end if;
  return json_build_object('id', r.id, 'nome', r.nome, 'setor', r.setor, 'token', r.token);
end $$;

-- Salvar tentativa ------------------------------------------------------
create or replace function public.trein_salvar_tentativa(
  p_token uuid, p_curso text, p_acertos int, p_total int, p_pontos int, p_respostas jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare pid uuid;
begin
  select id into pid from trein_participantes where token = p_token;
  if pid is null then raise exception 'Sessão expirada. Entre novamente.'; end if;
  if p_total < 1 or p_total > 50 or p_acertos < 0 or p_acertos > p_total
     or p_pontos < 0 or p_pontos > p_total * 1000 then
    raise exception 'Resultado inválido.';
  end if;
  insert into trein_tentativas (participante_id, curso, acertos, total, pontos, respostas)
  values (pid, p_curso, p_acertos, p_total, p_pontos, coalesce(p_respostas, '[]'::jsonb));
  return json_build_object('ok', true);
end $$;

-- Ranking (melhor tentativa por pessoa; sem curso = soma dos cursos) ----
create or replace function public.trein_ranking(p_curso text default null)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare res json;
begin
  with melhor as (
    select distinct on (t.participante_id, t.curso)
           t.participante_id, t.curso, t.pontos, t.acertos, t.total
    from trein_tentativas t
    order by t.participante_id, t.curso, t.pontos desc, t.criado_em asc
  ), base as (
    select p.id, p.nome, p.setor,
           sum(m.pontos)::int as pontos, sum(m.acertos)::int as acertos,
           sum(m.total)::int as total, count(*)::int as cursos
    from melhor m join trein_participantes p on p.id = m.participante_id
    where p_curso is null or m.curso = p_curso
    group by p.id, p.nome, p.setor
  )
  select coalesce(json_agg(json_build_object(
           'id', id, 'nome', nome, 'setor', setor, 'pontos', pontos,
           'acertos', acertos, 'total', total, 'cursos', cursos)
         order by pontos desc, nome), '[]'::json)
  into res from base;
  return res;
end $$;

-- Minhas tentativas ------------------------------------------------------
create or replace function public.trein_minhas_tentativas(p_token uuid)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare pid uuid; res json;
begin
  select id into pid from trein_participantes where token = p_token;
  if pid is null then raise exception 'Sessão expirada. Entre novamente.'; end if;
  select coalesce(json_agg(json_build_object('curso', curso, 'acertos', acertos, 'total', total,
           'pontos', pontos, 'criado_em', criado_em) order by criado_em desc), '[]'::json)
  into res from trein_tentativas where participante_id = pid;
  return res;
end $$;

-- Painel do gestor ------------------------------------------------------
create or replace function public.trein_painel(p_senha text)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  if not trein__confere('senha_gestor', p_senha) then
    raise exception 'Senha do gestor incorreta.';
  end if;
  return json_build_object(
    'participantes', (select coalesce(json_agg(json_build_object('id', id, 'nome', nome, 'setor', setor, 'criado_em', criado_em) order by nome), '[]'::json) from trein_participantes),
    'tentativas',    (select coalesce(json_agg(json_build_object('participante_id', participante_id, 'curso', curso, 'acertos', acertos, 'total', total, 'pontos', pontos, 'respostas', respostas, 'criado_em', criado_em) order by criado_em), '[]'::json) from trein_tentativas)
  );
end $$;

create or replace function public.trein_redefinir_pin(p_senha text, p_participante uuid, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  if not trein__confere('senha_gestor', p_senha) then
    raise exception 'Senha do gestor incorreta.';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN precisa ter 4 números.';
  end if;
  update trein_participantes set pin_hash = crypt(p_pin, gen_salt('bf')), token = gen_random_uuid()
  where id = p_participante;
  return json_build_object('ok', true);
end $$;

-- Permissões: o site (anon) só executa as funções públicas --------------
revoke all on function public.trein__confere(text, text) from public, anon, authenticated;
grant execute on function public.trein_registrar(text, text, text, text)          to anon, authenticated;
grant execute on function public.trein_entrar(text, text)                         to anon, authenticated;
grant execute on function public.trein_salvar_tentativa(uuid, text, int, int, int, jsonb) to anon, authenticated;
grant execute on function public.trein_ranking(text)                               to anon, authenticated;
grant execute on function public.trein_minhas_tentativas(uuid)                     to anon, authenticated;
grant execute on function public.trein_painel(text)                                to anon, authenticated;
grant execute on function public.trein_redefinir_pin(text, uuid, text)             to anon, authenticated;

-- ---------------------------------------------------------------------
-- Para trocar as senhas depois, rode (trocando os valores):
-- update public.trein_config set valor = extensions.crypt('NOVO_CODIGO', extensions.gen_salt('bf')) where chave = 'codigo_equipe';
-- update public.trein_config set valor = extensions.crypt('NOVA_SENHA',  extensions.gen_salt('bf')) where chave = 'senha_gestor';
