# Design — cloud-backend: Ranking por rodada (NEU-110)

> Parte da NEU-89 (ranking do evento por janela de tempo). Entrega a parte da nuvem
> para a banca final de 30/09; o site (NEU-111, web PR #11) já consome este contrato.
>
> **Convenção:** `[ev]` = verificado (comando/arquivo/API). `[hip]` = hipótese a
> confirmar na implementação. `[decisão]` = escolha do brainstorming, passível de revisão.
>
> Data: 2026-09-28. cloud-backend `main` @ `7de9b29`. Supabase ref `wtaulbdkgrnrtbfezaxw`.

---

## 1. Contexto e objetivo

- Hoje o ranking é um só, desde sempre: `get_leaderboard(p_metric text, p_limit int)`
  (migration `20260703091403_leaderboard_exclude_bots`) `[ev]`. Desempate por ordem
  alfabética (`order by s.score, s.display_name`), e empatados dividem o `rank` `[ev]`.
- Decisões de produto de 27/09 (comentário na NEU-89) `[ev]`: rodadas de 2 h com horário
  definido antes; prêmio para o 1º de cada rodada; **empate: vence quem fez o tempo
  primeiro**; entra quem tem conta confirmada e apelido; critério = melhor tempo; telão =
  a própria `/ranking`.
- O site já está pronto do lado dele: web PR #11 (NEU-111, em review) `[ev]` assume
  - `ranking_windows(id, name, starts_at, ends_at)` com leitura pública;
  - `get_leaderboard(p_metric, p_limit, p_from, p_to)`, `p_from`/`p_to` opcionais (ISO);
  - "Evento" = desde o **menor `starts_at`** cadastrado; "rodada atual" = `starts_at <= now() < ends_at`;
  - sem a tabela ou com deploy parcial, cai no ranking geral de hoje.
- Produção de pé em 2026-09-28: `get_leaderboard('best_time',5)` responde 200 com 2 linhas `[ev]`.

**Critério de sucesso (aceite da NEU-110):** com 2 rodadas cadastradas, cada uma mostra
só as corridas do seu horário; empate resolve por quem fez primeiro; a chamada antiga
`get_leaderboard('best_time', 50)` continua funcionando e devolve o mesmo ranking de hoje
(a menos da ordem de empates); testes SQL verdes na CI.

**Fora de escopo:** aviso a quem venceu (NEU-112/113), painel de operação para editar
rodadas e escolher métrica (NEU-114), outras métricas (NEU-67), índices novos.

---

## 2. Decisões

1. `[decisão]` **Contrato do web PR #11** é o contrato desta issue. Não há tabela/coluna
   separada para "início do evento": o site usa o menor `starts_at` como `p_from`.
   (A NEU-110 falava em guardar a data de início; dispensado para não retrabalhar o PR #11.)
2. `[decisão]` **Período por `finished_at`**, meio-aberto: `finished_at >= p_from` e
   `finished_at < p_to`. Parâmetro `null` = sem limite daquele lado. Coerente com o site
   (`starts_at <= now < ends_at`) e sem dupla contagem na virada entre rodadas.
3. `[decisão]` **Desempate por quem fez primeiro:** para cada jogador, a melhor corrida é
   a de menor duração; empatando na duração, a que terminou primeiro. O `rank` é
   `rank() over (order by score, achieved_at)` — só empate exato de tempo **e** de
   instante divide posição. Ordenação final: `score, achieved_at, display_name`.
4. `[decisão]` **Sem rodadas sobrepostas**, garantido no banco por exclusion constraint
   com `tstzrange(starts_at, ends_at, '[)')` e o operador `&&` (GiST nativo de range;
   não precisa de `btree_gist`). Rodadas encostadas (fim de uma = início da outra) são
   permitidas. Motivo: até a NEU-114, rodadas são editadas à mão no Supabase.
5. `[decisão]` **Escrita em `ranking_windows` só por SQL/`service_role`**; leitura pública
   (`anon`, `authenticated`) via RLS `using (true)`. A escrita pelo site fica para a
   NEU-114, com papel de operador desenhado lá.
6. `[decisão]` **Uma versão só de `get_leaderboard`:** a migration faz `drop function
   get_leaderboard(text, int)` e cria a de 4 parâmetros com defaults. Duas sobrecargas
   deixariam o PostgREST sem saber qual chamar para `{p_metric, p_limit}`.

---

## 3. Schema — `ranking_windows`

```sql
create table public.ranking_windows (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (char_length(btrim(name)) between 1 and 60),
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  created_at timestamptz not null default now(),
  constraint ranking_windows_valid_range check (ends_at > starts_at),
  constraint ranking_windows_no_overlap
    exclude using gist (tstzrange(starts_at, ends_at, '[)') with &&)
);

alter table public.ranking_windows enable row level security;
create policy ranking_windows_select_public on public.ranking_windows
  for select to anon, authenticated using (true);
grant select on public.ranking_windows to anon, authenticated;
```

- Sem policy de insert/update/delete → `anon`/`authenticated` não escrevem (RLS default deny).
- `service_role` e `postgres` (SQL editor) escrevem normalmente. `[hip]` no hospedado o
  default-privileges já concede DML a `service_role`; a migration concede explicitamente
  (`grant select, insert, update, delete ... to service_role`) para ficar igual no local.

---

## 4. Função — `get_leaderboard`

Assinatura nova (mesmos nomes de parâmetro, dois novos no fim, todos com default):

```sql
get_leaderboard(
  p_metric text        default 'best_time',
  p_limit  int         default 50,
  p_from   timestamptz default null,
  p_to     timestamptz default null
) returns table (rank int, display_name text, score numeric)
language sql stable security definer set search_path = public
```

Lógica (esboço):

```sql
with best as (
  select distinct on (pr.id)
         pr.display_name::text as display_name,
         extract(epoch from (rp.finished_at - rp.started_at))::numeric as score,
         rp.finished_at as achieved_at
  from profiles pr
  join players p       on p.user_id = pr.id
  join race_players rp on rp.player_id = p.id
  where p_metric = 'best_time'
    and pr.display_name is not null
    and rp.source = 'real'
    and rp.finished_at is not null
    and rp.finished_at > rp.started_at
    and (p_from is null or rp.finished_at >= p_from)
    and (p_to   is null or rp.finished_at <  p_to)
  order by pr.id, (rp.finished_at - rp.started_at) asc, rp.finished_at asc
)
select (rank() over (order by score asc, achieved_at asc))::int, display_name, score
from best
order by score asc, achieved_at asc, display_name asc
limit least(greatest(p_limit, 1), 1000);
```

Garantias mantidas: retorno exatamente `rank, display_name, score` (sem PII); só com
apelido; só `source='real'`; ignora não terminadas e duração ≤ 0; `p_limit` entre 1 e 1000;
métrica desconhecida → vazio. Grants refeitos: `revoke all ... from public`;
`grant execute ... to anon, authenticated`.

- Agrupar por `pr.id` (em vez de `display_name`) é equivalente hoje (`display_name` é
  `unique`, e `players.user_id` é `unique`), mas deixa explícito que é "por pessoa".
- `stable`: a função só lê; permite ao planner tratá-la como tal. A versão atual não
  declara volatilidade (default `volatile`) `[ev]`; mudar é seguro.
- `p_from > p_to` → vazio, sem erro (consequência natural dos filtros).

---

## 5. Migration e deploy

- **Uma migration**: `supabase/migrations/<ts>_ranking_windows.sql` com tabela + RLS +
  grants + `drop function public.get_leaderboard(text, int)` + `create function` nova +
  grants. O `supabase db push` aplica cada migration numa transação `[hip — confirmar]`,
  então não há janela sem função em produção.
- **Types:** regenerar `supabase/types/database.types.ts` (`supabase gen types typescript --local`).
- **Docs:** `docs/frontend-integration.md` §8 (novos parâmetros, tabela, desempate) e o
  resumo de arquitetura do `CLAUDE.md` (migrations/tabelas/funções).
- **Merge ≠ deploy (NEU-77):** após o merge, `supabase db push` em produção (precisa do
  token do Supabase do Nikolas) e conferência ao vivo: `get_leaderboard('best_time',50)`
  igual ao de antes; `select` em `ranking_windows` como `anon` responde 200.
- **Rodadas da banca:** cadastrar em produção por SQL depois do deploy (operação, não
  migration). Horários a combinar com o time.

---

## 6. Testes (`supabase/tests/leaderboard_windows_test.sql`)

TDD: o teste é escrito antes e falha contra o schema atual. Seed determinístico
(uuids e timestamps fixos), limpa o próprio seed no fim, `assert` reais.

| # | Cenário | Esperado |
|---|---|---|
| 1 | 2 rodadas (R1 10:00–12:00, R2 12:00–14:00); corridas em cada; `get_leaderboard` chamado com `p_from`/`p_to` de cada rodada | cada rodada mostra só as suas |
| 2 | corrida com `finished_at` = 12:00 exato | entra em R2, não em R1 |
| 3 | dois jogadores com a mesma duração, terminadas em horários diferentes | quem terminou primeiro fica com `rank` 1, o outro com 2 |
| 4 | A faz 30 s às 10:10 e de novo às 11:50; B faz 30 s às 11:00 | A fica à frente de B (vale a primeira vez que A fez 30 s) |
| 5 | chamada sem período / chamada antiga `('best_time', 50)` | ranking geral (todas as corridas) |
| 6 | só `p_from` (modo "Evento") | ignora corridas antes de `p_from` |
| 7 | `anon` lê `ranking_windows` | ok |
| 8 | `anon`/`authenticated` tentam `insert` | erro (RLS) |
| 9 | rodada sobreposta / `ends_at <= starts_at` | erro (constraint) |
| 10 | catálogo | existe exatamente uma `get_leaderboard` |

Não-regressão: `leaderboard_test.sql` e `leaderboard_bots_test.sql` seguem verdes sem
edição (no empate Bob/Dave os `finished_at` são idênticos, então continuam dividindo o
rank 1 `[ev — seed do teste]`). Suíte completa: todos os `supabase/tests/*.sql` + `deno test`.

---

## 7. Riscos

- **Deploy parcial** (tabela criada e função não): o site cai no ranking geral (tratado
  no PR #11) `[ev — lib/ranking-data.ts do PR #11]`.
- **Fuso:** `timestamptz` guarda em UTC; o site formata em São Paulo. Quem cadastra a
  rodada por SQL deve escrever o offset (`'2026-09-30 14:00-03'`).
- **Dados de teste antigos no "Evento":** saem naturalmente se a primeira rodada começar
  depois deles.
