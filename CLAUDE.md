# CLAUDE.md — cloud-backend (API do NeuroRace)

Guia para agentes de IA (e humanos) trabalharem neste repo. Leia antes de mexer.

## Princípios (não-negociáveis)
- **Honestidade brutal:** problemas antes de positivos; sem suavizar.
- **Evidência, nunca inferência:** não afirme "pronto/passa/deployado" sem prova (output de comando, SHA+diff, resposta HTTP, caminho de arquivo). Se não pôde verificar, diga "não verifiquei — assumindo X" e pare.
- **Não-regressão:** não declare concluído sem a suíte relevante verde. Toda mudança é aditiva/reversível por padrão.
- **Escopo:** faça exatamente o pedido; sinalize o resto, não toque sem ok.
- **PT-BR no chat.**

## O que é
API do NeuroRace no **Supabase** (não há servidor próprio). Recebe o resultado de corridas EEG do `edge-service`, guarda em Postgres, e serve dados para o front (dashboard próprio + ranking). O front fala **direto com o Supabase** (`@supabase/supabase-js` + RLS); a escrita vem só do edge.

Projeto hospedado: ref **`wtaulbdkgrnrtbfezaxw`** · endpoint de ingest: `https://wtaulbdkgrnrtbfezaxw.supabase.co/functions/v1/ingest-race`.

## Arquitetura (o que existe hoje — evidência: `supabase/migrations/`)
- **Edge Function `ingest-race`** (`supabase/functions/ingest-race/`, Deno): recebe o POST do edge, valida token (`x-edge-ingest-token`, `verify_jwt=false`) e o contrato, chama `ingest_race` via rpc com `service_role`. Arquivos: `index.ts` (handler), `auth.ts` (compare tempo-constante), `contract.ts` (validação).
- **Postgres (16 migrations)**:
  - `init_schema` — 4 tabelas de **dados**: `players` (jogador por email), `races`, `race_players` (resultado por jogador), `telemetry_points` (EEG). RLS ON.
  - `ingest_race_fn` + `fix_ingest_race` — função `ingest_race(jsonb)` transacional idempotente.
  - `claim_trigger` — `handle_email_confirmed`: vincula `players.user_id` quando o email é confirmado.
  - `grant_service_role` — grants DML ao `service_role`.
  - `rls_read_policies` — 4 policies `for select to authenticated` (own-data) nas tabelas de dados.
  - `profiles` — tabela `profiles` (alias `display_name` citext único) + RLS own + trigger `handle_new_user_profile` (cria profile no signup).
  - `get_leaderboard` — função `security definer` pública (ranking por `best_time`, sem PII).
  - `leaderboard_exclude_bots` — `get_leaderboard` só conta `source = 'real'`.
  - `ranking_windows` — tabela de rodadas (leitura pública, sem sobreposição, escrita só por SQL/`service_role`) + `get_leaderboard(p_metric, p_limit, p_from, p_to)` com período e desempate por quem fez primeiro (NEU-110).
  - `player_phone` — NEU-159: `players.phone` (+55DDD9XXXXXXXX), `email` opcional (um dos dois), sai o `unique(user_id)` (conta com jogador do e-mail e do celular), `ingest_race` aceita `player_phone`, trigger `on_auth_phone_confirmed` (`handle_phone_confirmed`). Volta testada em `supabase/rollbacks/`: a ordem está no topo do `.down.sql` (função anterior primeiro, depois a parte A; o `.down-schema.sql` só com 0 jogadores de celular e 0 contas com 2 jogadores).
  - `telegram_subscriptions` — bot do Telegram (NEU-30): `telegram_subscriptions` (chat ↔ e-mail do estande, e-mail normalizado) e `telegram_notifications` (avisos já enviados, idempotência). **Só `service_role`**; o bot só manda aviso + link, nunca dados da corrida (LGPD).
  - `premiacao` — NEU-167: `premiacao_config` (regras, começa desligada), `premiacao_rodadas` (rodada fechada no fim + carência; só conta corrida que chegou até o corte), `premios` (uma linha por vez de cada conta na rodada, código de 6 dígitos; a fila dá até `limite_fila` vezes entre os elegíveis; corrida abaixo de `piso_tempo_s` — 15 s, só por SQL — não concorre; índices únicos: um dono por rodada, um prêmio por conta no evento) e `premiacao_registro`. `premiacao_tick(p_agora)` roda no `pg_cron` (agendado à mão, ver o rollback). Leitura: `get_my_prize()` (só `authenticated`, o próprio) e `get_official_winners()` (público, sem contato). Tabelas e funções internas sem acesso de anon/authenticated. Volta testada em `supabase/rollbacks/`.
  - `premiacao_operadores` — NEU-168: `operadores` (e-mails do time, só por SQL) e as funções do painel `/operador`: `op_painel`, `op_validar_codigo`, `op_acao`, `op_config` (só `authenticated`; quem não é operador com e-mail confirmado recebe 42501). Cada ação vai para `premiacao_registro` com o e-mail. Toda escrita tem WHERE: as sessões do PostgREST usam `safeupdate`. Volta e religar em `supabase/rollbacks/`.
  - `mensagens` — NEU-112: caixa de saída das mensagens da premiação. `mensagens_config` (e-mail e tipos começam desligados; teto de 300/24 h com reserva de 50 para o prêmio; 3 novas tentativas), `mensagens` (chave única, validade, estados `pendente/enviada/falhou/expirada/cancelada/bloqueada`) e `mensagens_bloqueio` (lista de "não enviar" por canal + contato). Quem enfileira usa `mensagem_enfileirar(...)` e `mensagens_destino_email(user, player)`; o envio usa `mensagens_preparar(canal, agora, limite)` (trava de 5 min com `envio_id`), `mensagem_resultado(...)` (só o dono da trava decide uma falha) e `mensagem_soltar`; os links usam `mensagem_bloquear` e `mensagem_recusar_premio` (chama `premio_passar`). Só `service_role`. Instala `pg_net`; o job `mensagens-envio` é agendado à mão (cabeçalho da migration). Volta testada em `supabase/rollbacks/`.
  - `avisos_corrida` — NEU-170: `avisos_corrida_tick(p_agora)` (job no `pg_cron`, agendado à mão) só **lê** `race_players` e enfileira na caixa de saída da NEU-112: com conta, "corrida registrada" (tempo + posição do `get_leaderboard` da rodada) no e-mail confirmado; sem conta, só o convite (sem tempo nem posição) no e-mail do estande. Um aviso por pessoa a cada `intervalo_min` (30), com a melhor corrida dos primeiros `espera_min` (10). `avisos_corrida_config` começa desligada; `avisos_corrida` guarda a decisão de cada corrida. `mensagem_formata_tempo` = `formatDuration` do site. Só `service_role`. Volta testada em `supabase/rollbacks/`.
- **Tabelas:** `players, races, race_players, telemetry_points, profiles, ranking_windows, telegram_subscriptions, telegram_notifications, premiacao_config, premiacao_rodadas, premios, premiacao_registro, operadores, mensagens_config, mensagens, mensagens_bloqueio, avisos_corrida_config, avisos_corrida`. **Funções:** `ingest_race, handle_email_confirmed, handle_phone_confirmed, handle_new_user_profile, get_leaderboard, premiacao_tick, premiacao_registra_erro, premiacao_candidatos, premio_dar_vez, premio_passar, premio_novo_codigo, get_my_prize, get_official_winners, premio_dar_vez_ate, premiacao_operador_atual, premiacao_mascara_contato, premiacao_op_painel, premiacao_op_validar, premiacao_op_acao, premiacao_op_config, op_painel, op_validar_codigo, op_acao, op_config, mensagens_contato, mensagem_enfileirar, mensagens_destino_email, mensagens_preparar, mensagem_resultado, mensagem_soltar, mensagem_bloquear, mensagem_recusar_premio, mensagem_formata_tempo, avisos_corrida_pessoa, avisos_corrida_tick`.
- **Edge Functions `send-messages` e `message-actions`** (NEU-112, `verify_jwt=false`): `send-messages` é chamada pelo `pg_cron` com `x-cron-token`, manda pela Brevo e grava o resultado; `message-actions` recebe por POST o token assinado (HMAC, `_shared/links.ts`) dos links "Parar de receber" e "Não vou poder". Sem a Brevo configurada, `send-messages` responde 503 e não prepara nada.

## Rodar local (precisa de Docker)
```bash
docker info            # Docker precisa estar de pé
supabase start
supabase db reset      # aplica TODAS as migrations do zero
```

## Testar (é assim que se prova não-regressão)
```bash
DB="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
# Banco: roda TODOS os testes em supabase/tests/ via glob (teste novo entra sozinho)
for f in supabase/tests/*.sql; do echo "== $f =="; psql "$DB" -v ON_ERROR_STOP=1 -f "$f" || exit 1; done
# Função (Deno)
deno test supabase/functions/ingest-race/
# Integração e2e (requer `supabase functions serve ingest-race --env-file supabase/functions/.env`)
EDGE_INGEST_TOKEN=dev-only-change-me ./scripts/proof-ingest.sh
```
Estado verde de referência (verificado 2026-10-21): **14 testes SQL OK + `36 passed | 0 failed` no Deno**. **Não declare concluído sem isso verde.**

## Convenções (best practices deste repo)
- **Migrations são aditivas** — não edite uma já aplicada em produção; crie uma nova (`supabase migration new <nome>`). Exceção: uma migration ainda **não** mergeada/deployada (PR aberto) pode ser editada in-place.
- **Escrita nas 4 tabelas de dados só via `service_role`** (o ingest). RLS de leitura é own-data (`auth.uid()`). `profiles` é a única tabela com escrita via RLS (o usuário edita o próprio `display_name`).
- **Leaderboard nunca expõe PII** — `get_leaderboard` devolve só `rank/display_name/score` (sem email/ids). É `security definer` + `set search_path`.
- **Toda feature = migration + teste + review.** Testes SQL usam `assert` reais (não no-op) e limpam o próprio seed no fim.
- **`mailer_autoconfirm` DEVE ser `false` em produção** (confirmação de email obrigatória) — é o que sustenta o vínculo seguro de corridas.

## Fluxo de trabalho
1. Branch a partir de `main` (`git checkout main && git pull`, depois `git checkout -b feat/...`). Não commite direto em `main` (protegida; push é bloqueado por hook).
2. TDD por task (teste falha → implementa → passa → commit). Para planos grandes, use `superpowers:subagent-driven-development` (implementer + review por task) e `/pr-review-toolkit:review-pr` no fim.
3. **Worktrees:** prefira-as por padrão em trabalhos de implementação — isolam a mudança e permitem mais de uma sessão/agente em paralelo sem colidir no working tree (`superpowers:using-git-worktrees`). Dispensáveis para trabalhos de análise/investigação (sem escrita de código).
4. PR → review → merge. Depois: `supabase db push` no hospedado (só DDL; **verifique read-only e NÃO toque nos dados reais do edge**).
5. Deletar a branch após o merge (local e remoto).

## Segredos / tokens (NUNCA ecoar, NUNCA commitar)
- Tokens ficam em **variáveis de ambiente prefixadas com `NEURORACE_`** (deixa claro o projeto e evita colisão com vars de outros projetos nesta máquina): `NEURORACE_SUPABASE_ACCESS_TOKEN` e `NEURORACE_LINEAR_API_KEY`.
- **Já estão configurados nesta máquina** (macOS Keychain → env via `~/.zshrc` que faz source de `~/.neurorace-secrets.sh`). Numa sessão nova as env vars **já vêm populadas** — apenas **use** `$NEURORACE_SUPABASE_ACCESS_TOKEN` / `$NEURORACE_LINEAR_API_KEY`, não refaça o setup. (O bloco "Setup de tokens" abaixo é só para uma máquina NOVA.) Setup global por-usuário: vale em qualquer diretório desta conta, não só neste repo.
- Use nos comandos (o valor expande em runtime; **nunca** o imprima):
  - **curl / Management API / Linear:** `curl -H "Authorization: Bearer $NEURORACE_SUPABASE_ACCESS_TOKEN" ...`
  - **CLI `supabase`** (espera a var padrão `SUPABASE_ACCESS_TOKEN`): mapeie **inline** → `SUPABASE_ACCESS_TOKEN=$NEURORACE_SUPABASE_ACCESS_TOKEN supabase <cmd>`.
- `.env`, `supabase/functions/.env`, `.secret.prod.env` são gitignored. `EDGE_INGEST_TOKEN` de produção (secret da Edge Function) fica em `.secret.prod.env` (local, `chmod 600`).
- **NÃO** rode `supabase login` com token efêmero (grava em disco); prefira o token na env (mapeado inline como acima).

### Setup de tokens (só numa máquina NOVA — já feito nesta)
```bash
# 1) guarde os tokens no Keychain (não commite, não cole em chat público)
security add-generic-password -s neurorace-supabase -a "$USER" -w '<SUPABASE_PAT>'
security add-generic-password -s neurorace-linear   -a "$USER" -w '<LINEAR_API_KEY>'
# 2) faça o ~/.zshrc dar source no helper (o ~/.neurorace-secrets.sh já foi criado, lê do Keychain):
echo '[ -f ~/.neurorace-secrets.sh ] && source ~/.neurorace-secrets.sh' >> ~/.zshrc
# 3) abra um shell novo e confirme (sem revelar o valor):
[ -n "$NEURORACE_SUPABASE_ACCESS_TOKEN" ] && echo "SUPABASE ok" ; [ -n "$NEURORACE_LINEAR_API_KEY" ] && echo "LINEAR ok"
```

## Ponteiros
- Specs/planos: `docs/superpowers/specs/` e `docs/superpowers/plans/`.
- Guia do front (como conectar/ler): `docs/frontend-integration.md`.
- Contrato de escrita edge→cloud: `../edge-service/docs/cloud-sync-contract.md`.
- Linear: time **NEU**, projeto **cloud-backend**. Issues relevantes: NEU-58 (ingest), NEU-63 (leitura), NEU-65 (ranking), NEU-67 (novas métricas), NEU-66 (game: "parou no meio").
- `artifacts/` e `inbox/` são scratch **não versionado** (gitignored) — não commite.
