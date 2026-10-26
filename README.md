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
1. Abra o projeto Supabase (pode ser um já existente: tudo usa o prefixo `trein_`).
2. SQL Editor → cole e rode `supabase/schema.sql` inteiro.
3. Senhas iniciais: **código da equipe `1978`** (pedido no primeiro acesso) e
   **senha do gestor `gestor1978`**. Para trocar, use os comandos no final do arquivo SQL.

## 2. Ligar o site ao banco
No `index.html`, procure `const CONFIG` e preencha:
```js
SUPABASE_URL: 'https://SEU-PROJETO.supabase.co',   // sem /rest/v1 no final
SUPABASE_ANON_KEY: 'chave anon public'              // Settings → API
```
Com esses campos vazios a plataforma roda em **modo demonstração** (dados só no aparelho,
com 4 participantes de exemplo).

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
- O gestor pode redefinir o PIN de quem esquecer.
