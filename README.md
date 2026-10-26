# Academia Drive — plataforma de treinamento Drive in Burger

Cursos com slides, avaliação cronometrada (pontos por rapidez), ranking da equipe,
celebração ao atingir 80% e painel do gestor com as perguntas mais erradas.

## Estrutura
```
index.html            plataforma completa (HTML + CSS + JS)
slides/atendimento/   Atendimento de Excelência (8 slides)
slides/saladas/       Ilha de Saladas (15 slides)
slides/lanches/       Fichas Técnicas e Montagem de Lanches (43 slides)
slides/fritas/        Porções de Batata Frita (11 slides)
slides/sobremesas/    Sobremesas (26 slides)
slides/fritadeira/    Filtragem da Fritadeira, versão com 2 filtragens/dia (13 slides)
assets/logo.png       (opcional) coloque aqui a logo oficial em PNG transparente
supabase/schema.sql   banco de dados (tabelas + funções)
netlify.toml
```

## 1. Banco no Supabase
1. SQL Editor → cole e rode `supabase/schema.sql` inteiro. Pode rodar de novo num banco
   que já tem a versão anterior: as tabelas e as notas ficam, só as funções mudam.
2. Authentication → Users → **Add user → Create new user**: e-mail e senha do gestor,
   com **Auto Confirm User** marcado.
3. No SQL Editor, libere esse e-mail como gestor:
   ```sql
   insert into public.trein_gestores (email, nome) values ('email@do-gestor.com', 'Nome do gestor');
   ```
   Repita os passos 2 e 3 para cada gestor.
4. Recomendado: em Authentication → Sign In / Providers, desligue **Allow new users to sign up**,
   para ninguém criar conta sozinho. Mesmo que crie, só quem está em `trein_gestores` abre o painel.

Para retirar alguém da gestão: `delete from public.trein_gestores where email = '...';`
Senha esquecida do gestor: redefina em Authentication → Users.

## 2. Ligar o site ao banco
No `index.html`, procure `const CONFIG` e preencha:
```js
SUPABASE_URL: 'https://SEU-PROJETO.supabase.co',   // sem /rest/v1 no final
SUPABASE_ANON_KEY: 'chave anon public'              // Settings → API
```
Com esses campos vazios a plataforma roda em **modo demonstração** (dados só no aparelho,
com 4 colaboradores de exemplo que entram com o PIN 1234; gestor `gestor@demo.com` / `gestor1978`).

## Como a equipe usa
- **Gestor**: "Área do gestor" → e-mail e senha. Cadastra colaboradores (nome, setor, PIN inicial),
  muda setor, redefine PIN e desativa ou reativa o acesso. Desativado não entra e sai do ranking;
  as notas ficam guardadas.
- **Colaborador**: entra com nome e PIN que o gestor passou. Não existe autocadastro.

## 3. Publicar na Netlify
Suba a pasta num repositório GitHub (ex.: `pinhonc/academia-drive`) e conecte na Netlify,
ou arraste a pasta inteira no painel da Netlify (não há etapa de build).

## Editar conteúdo
No `index.html`, a constante `CURSOS` guarda slides, textos e perguntas.
Em cada pergunta a **primeira opção é a correta** (a ordem é embaralhada no quiz).
`porTentativa` define quantas perguntas são sorteadas por tentativa (15 por curso; 10 em Batata Frita).
As imagens de cada curso ficam em `slides/<id do curso>/01.jpg, 02.jpg...`.
`TEMPO_POR_PERGUNTA` e `APROVACAO` ficam logo abaixo de `CONFIG`.

## Regras do quiz
- 30 s por pergunta; acerto vale 500 + até 500 pela rapidez (máx. 1.000).
- Aprovação com 80% de acertos (12 de 15; 8 de 10 em Batata Frita).
- A avaliação libera depois que o colaborador chega ao último slide do curso.
- O ranking usa a melhor tentativa de cada pessoa; o ranking geral soma os cursos.
