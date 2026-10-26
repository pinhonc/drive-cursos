-- =====================================================================
-- Academia Drive — banco no Supabase (versão 2: gestor com login)
-- Rode este arquivo inteiro no SQL Editor do projeto Supabase.
-- Pode rodar de novo num banco que já tem a versão 1: as tabelas e os
-- dados ficam; só as funções são atualizadas.
--
-- Como funciona:
--  • Gestor entra com e-mail e senha (Supabase Auth). Só quem está na
--    tabela trein_gestores acessa o painel.
--  • O gestor cadastra os colaboradores (nome, setor e PIN).
--  • Colaborador entra com nome + PIN. Não existe mais autocadastro.
--
-- Tudo usa o prefixo "trein_" para não conflitar com outros apps.
-- As tabelas ficam fechadas (RLS sem políticas); o site só acessa os
-- dados pelas funções abaixo.
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
alter table public.trein_participantes add column if not exists ativo boolean not null default true;
alter table public.trein_participantes add column if not exists criado_por text;

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

create table if not exists public.trein_gestores (
  email     text primary key,
  nome      text,
  criado_em timestamptz not null default now()
);

alter table public.trein_participantes enable row level security;
alter table public.trein_tentativas    enable row level security;
alter table public.trein_config        enable row level security;
alter table public.trein_gestores      enable row level security;

-- Funções da versão 1 que dependiam da senha fixa do gestor ou do
-- autocadastro. São substituídas pelas funções com login, mais abaixo.
drop function if exists public.trein_registrar(text, text, text, text);
drop function if exists public.trein_painel(text);
drop function if exists public.trein_redefinir_pin(text, uuid, text);

-- ---------------------------------------------------------------------
create or replace function public.trein__norm(p text) returns text
language sql immutable as $$
  select lower(regexp_replace(trim(coalesce(p, '')), '\s+', ' ', 'g'))
$$;

-- Quem está logado é gestor?
create or replace function public.trein__eh_gestor() returns boolean
language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from trein_gestores
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  )
$$;

create or replace function public.trein__exige_gestor() returns void
language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not trein__eh_gestor() then
    raise exception 'Acesso restrito ao gestor. Entre com o e-mail cadastrado como gestor.';
  end if;
end $$;

-- Login do colaborador (nome + PIN) ------------------------------------
create or replace function public.trein_entrar(p_nome text, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare r trein_participantes;
begin
  select * into r from trein_participantes where nome_norm = trein__norm(p_nome);
  if r.id is null or crypt(coalesce(p_pin, ''), r.pin_hash) <> r.pin_hash then
    raise exception 'Nome ou PIN incorretos.';
  end if;
  if not r.ativo then
    raise exception 'Seu acesso está desativado. Fale com o seu gestor.';
  end if;
  return json_build_object('id', r.id, 'nome', r.nome, 'setor', r.setor, 'token', r.token);
end $$;

-- Salvar tentativa ------------------------------------------------------
create or replace function public.trein_salvar_tentativa(
  p_token uuid, p_curso text, p_acertos int, p_total int, p_pontos int, p_respostas jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare pid uuid;
begin
  select id into pid from trein_participantes where token = p_token and ativo;
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
    where p.ativo and (p_curso is null or m.curso = p_curso)
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
  select id into pid from trein_participantes where token = p_token and ativo;
  if pid is null then raise exception 'Sessão expirada. Entre novamente.'; end if;
  select coalesce(json_agg(json_build_object('curso', curso, 'acertos', acertos, 'total', total,
           'pontos', pontos, 'criado_em', criado_em) order by criado_em desc), '[]'::json)
  into res from trein_tentativas where participante_id = pid;
  return res;
end $$;

-- ===================== Funções do gestor (exigem login) =================

create or replace function public.trein_gestor_eu()
returns json language plpgsql security definer set search_path = public, extensions as $$
declare g trein_gestores;
begin
  perform trein__exige_gestor();
  select * into g from trein_gestores where lower(email) = lower(auth.jwt() ->> 'email');
  return json_build_object('email', g.email, 'nome', g.nome);
end $$;

create or replace function public.trein_painel()
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  perform trein__exige_gestor();
  return json_build_object(
    'participantes', (select coalesce(json_agg(json_build_object('id', id, 'nome', nome, 'setor', setor, 'ativo', ativo, 'criado_em', criado_em, 'criado_por', criado_por) order by nome), '[]'::json) from trein_participantes),
    'tentativas',    (select coalesce(json_agg(json_build_object('participante_id', participante_id, 'curso', curso, 'acertos', acertos, 'total', total, 'pontos', pontos, 'respostas', respostas, 'criado_em', criado_em) order by criado_em), '[]'::json) from trein_tentativas)
  );
end $$;

create or replace function public.trein_gestor_cadastrar(p_nome text, p_setor text, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare r trein_participantes;
begin
  perform trein__exige_gestor();
  if length(trim(coalesce(p_nome, ''))) < 3 then
    raise exception 'Digite o nome e o sobrenome do colaborador.';
  end if;
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN precisa ter 4 números.';
  end if;
  if exists (select 1 from trein_participantes where nome_norm = trein__norm(p_nome)) then
    raise exception 'Já existe um colaborador com esse nome. Acrescente o sobrenome para diferenciar.';
  end if;
  insert into trein_participantes (nome, nome_norm, setor, pin_hash, criado_por)
  values (regexp_replace(trim(p_nome), '\s+', ' ', 'g'), trein__norm(p_nome), p_setor,
          crypt(p_pin, gen_salt('bf')), auth.jwt() ->> 'email')
  returning * into r;
  return json_build_object('id', r.id, 'nome', r.nome, 'setor', r.setor);
end $$;

create or replace function public.trein_gestor_atualizar(p_id uuid, p_setor text, p_ativo boolean)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  perform trein__exige_gestor();
  update trein_participantes
     set setor = coalesce(p_setor, setor),
         ativo = coalesce(p_ativo, ativo),
         token = case when p_ativo is false then gen_random_uuid() else token end
   where id = p_id;
  if not found then raise exception 'Colaborador não encontrado.'; end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.trein_gestor_redefinir_pin(p_id uuid, p_pin text)
returns json language plpgsql security definer set search_path = public, extensions as $$
begin
  perform trein__exige_gestor();
  if coalesce(p_pin, '') !~ '^[0-9]{4}$' then
    raise exception 'O PIN precisa ter 4 números.';
  end if;
  update trein_participantes set pin_hash = crypt(p_pin, gen_salt('bf')), token = gen_random_uuid()
  where id = p_id;
  if not found then raise exception 'Colaborador não encontrado.'; end if;
  return json_build_object('ok', true);
end $$;

-- Permissões -------------------------------------------------------------
revoke all on function public.trein__eh_gestor()   from public, anon, authenticated;
revoke all on function public.trein__exige_gestor() from public, anon, authenticated;

grant execute on function public.trein_entrar(text, text)                                  to anon, authenticated;
grant execute on function public.trein_salvar_tentativa(uuid, text, int, int, int, jsonb)  to anon, authenticated;
grant execute on function public.trein_ranking(text)                                        to anon, authenticated;
grant execute on function public.trein_minhas_tentativas(uuid)                              to anon, authenticated;

revoke all on function public.trein_gestor_eu()                               from public, anon;
revoke all on function public.trein_painel()                                  from public, anon;
revoke all on function public.trein_gestor_cadastrar(text, text, text)        from public, anon;
revoke all on function public.trein_gestor_atualizar(uuid, text, boolean)     from public, anon;
revoke all on function public.trein_gestor_redefinir_pin(uuid, text)          from public, anon;
grant execute on function public.trein_gestor_eu()                            to authenticated;
grant execute on function public.trein_painel()                               to authenticated;
grant execute on function public.trein_gestor_cadastrar(text, text, text)     to authenticated;
grant execute on function public.trein_gestor_atualizar(uuid, text, boolean)  to authenticated;
grant execute on function public.trein_gestor_redefinir_pin(uuid, text)       to authenticated;

-- =====================================================================
-- DEPOIS DE RODAR: cadastre quem é gestor (troque pelo e-mail real).
-- O e-mail precisa ser o mesmo do usuário criado em
-- Authentication → Users → Add user.
--
-- insert into public.trein_gestores (email, nome) values ('email@exemplo.com', 'Nome do gestor');
-- =====================================================================
