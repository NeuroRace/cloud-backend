# Guia de integração do Frontend — NeuroRace cloud-backend

> **TL;DR (não técnico):** o frontend conversa **direto com o Supabase** (não há uma API
> própria a chamar). Você faz login do usuário e lê **as corridas e a telemetria DELE** —
> a segurança (cada um só vê o seu) é garantida pelo banco. Hoje o banco está **vazio**: só
> vai aparecer dado quando o edge gravar a 1ª corrida real de um e-mail que o usuário depois
> cadastrar com o **mesmo e-mail** e confirmar.

## 1. Modelo de acesso (decidido)
- **Direto via `@supabase/supabase-js` + RLS.** Sem API custom para leitura. Best practice Supabase e o caminho mais rápido para vocês se virarem sozinhos.
- O que existe hoje: **leitura own-data** (o usuário lê o próprio `players`/`races`/`race_players`/`telemetry_points`) e **auth** (cadastro/login por e-mail).
- O que **NÃO** existe ainda: qualquer endpoint de escrita pelo front (a escrita vem só do edge). Ranking público já existe (ver seção 8).

## 2. Conexão
Instale o cliente no projeto de vocês: `npm install @supabase/supabase-js`

```ts
import { createClient } from '@supabase/supabase-js'
import type { Database } from './database.types' // ver seção 6

const supabase = createClient<Database>(
  'https://wtaulbdkgrnrtbfezaxw.supabase.co',
  'sb_publishable_JpFFIWudbZ3GxR04QINxog_GqGk7dpw', // publishable key (PUBLICA — pode ir no bundle do front). NUNCA use service_role/secret aqui.
)
```
- A **URL** é pública. A **publishable key** (`sb_publishable_...`) é feita para ir no frontend (não é segredo). **Nunca** use a `service_role`/`secret` key no front.

## 3. Auth (cadastro e login por e-mail)
Confirmação de e-mail está **ligada** (obrigatória) — é o que garante a segurança do vínculo das corridas.
```ts
// cadastro
await supabase.auth.signUp({ email, password })
// o usuário recebe um e-mail de confirmação; só depois de confirmar a sessão fica válida.

// login
await supabase.auth.signInWithPassword({ email, password })

// sessão atual
const { data: { session } } = await supabase.auth.getSession()
```
> **PENDENTE (precisa do Pedro):** a URL de redirect do e-mail de confirmação precisa estar
> liberada no Supabase. Hoje só `http://localhost:3000` está em `site_url` e a allow-list
> está vazia. Se o app de vocês rodar em outra URL/porta (ex.: Vite em `5173`), me passem a
> URL e o Pedro adiciona em **Authentication > URL Configuration** (`Site URL` + `Redirect URLs`).
> Enquanto isso, dá para confirmar usuários de teste manualmente no painel
> (**Authentication > Users**).

## 4. Lendo os dados do usuário (a RLS já escopa para ele)
Depois de logado, basta consultar — o banco devolve **apenas o que é do usuário**:
```ts
// minhas corridas
const { data: races } = await supabase
  .from('races')
  .select('id, started_at')
  .order('started_at', { ascending: false })

// meus resultados por corrida
const { data: racePlayers } = await supabase
  .from('race_players')
  .select('id, race_id, player_slot, source, started_at, finished_at')

// minha telemetria (amostras de EEG)
const { data: telemetry } = await supabase
  .from('telemetry_points')
  .select('t, attention, meditation, poor_signal_level, signal_status, eeg_power')
  .order('t')
```
- Sem login (anon), essas queries voltam **vazias** (não erro) — comportamento esperado.
- Não é possível ler dados de **outro** usuário (a RLS bloqueia — testado).

## 5. Modelo de dados (4 tabelas)
- **`players`** — jogador canônico por **e-mail ou celular** (NEU-159: `email` e `phone` opcionais, pelo menos um; `phone` no formato `+5511987654321`). `user_id` liga à conta — é preenchido **automaticamente** quando o usuário **confirma o e-mail** (trigger `on_auth_email_confirmed`) ou **confirma o celular** por SMS (trigger `on_auth_phone_confirmed`; o Supabase guarda o celular sem o `+`, o trigger normaliza). Enquanto não confirma, fica `null` e a RLS não retorna nada para aquele usuário.
  - **Uma conta pode ter dois jogadores** (o do e-mail e o do celular). As queries do §4 já trazem as corridas dos dois; o ranking mostra a pessoa uma vez, com o melhor tempo. Não use `.single()` em `players`.
- **`races`** — a corrida (`id`, `started_at`). O fim é por-jogador (em `race_players`).
- **`race_players`** — resultado de um jogador numa corrida (`player_slot` esperado 1|2, `started_at`, `finished_at`).
- **`telemetry_points`** — amostras de EEG (`t`, `attention`, `meditation` — esperado 0..100, validado na ingestão, **sem CHECK no banco**; `poor_signal_level`, `signal_status`, `eeg_power` jsonb com as bandas do device).

## 6. Types TypeScript
- Já há um arquivo gerado em `supabase/types/database.types.ts` (copiem para o projeto de vocês).
- Para regenerar quando o schema mudar: `supabase gen types typescript --project-id wtaulbdkgrnrtbfezaxw > database.types.ts` (precisa do token/login do Supabase) ou `--local` num checkout do `cloud-backend`.

## 7. Alias (display_name) — setar no cadastro
Cada usuário tem um `display_name` **único** (case-insensitive), usado no ranking. Ele começa NULL e o usuário escolhe:
```ts
// depois do signup/login, setar o nome:
const { error } = await supabase
  .from('profiles')
  .update({ display_name: nome })
  .eq('id', user.id)
if (error?.code === '23505') {
  // 23505 = unique_violation -> nome já em uso, pedir outro
}
```
Regras: 3–20 caracteres, sem espaço nas pontas. O usuário **só aparece no ranking depois de ter um nome**.

## 8. Ranking / leaderboard (público)
```ts
// metric: 'best_time' (por enquanto). Retorna [{ rank, display_name, score }]
const { data } = await supabase.rpc('get_leaderboard', { p_metric: 'best_time', p_limit: 50 })
// período opcional (NEU-110): conta só corridas com p_from <= finished_at < p_to
const { data: rodada } = await supabase.rpc('get_leaderboard', {
  p_metric: 'best_time', p_limit: 50, p_from: r.starts_at, p_to: r.ends_at,
})
// score de best_time = duração da melhor corrida em SEGUNDOS (menor = melhor)
```
- É **público** (funciona logado ou não). Devolve só `rank`, `display_name`, `score` — sem e-mail.
- **Desempate:** mesmo tempo → vence quem fez primeiro (rank distinto). Só empate exato de tempo e instante divide o rank.
- **Rodadas:** `supabase.from('ranking_windows').select('id, name, starts_at, ends_at')` — leitura pública, sem sobreposição. "Evento" = desde o menor `starts_at`; "rodada atual" = `starts_at <= agora < ends_at`. Escrita só pelo SQL do Supabase (até a NEU-114), **sempre com offset**: `'2026-09-30 14:00-03'` (o editor roda em UTC; sem offset a rodada fica 3 h deslocada).
- Para destacar "você", compare `display_name` com o do próprio usuário (lido de `profiles`).

## 8.1 Prêmio da rodada (NEU-167)
O banco fecha a rodada no fim + carência (padrão 5 min), congela o 1º elegível (por conta, um prêmio por conta no evento) e gera um código de 6 dígitos. Corrida que chega à nuvem depois do fechamento não troca o vencedor. Tudo começa desligado (`premiacao_config.premiacao_ligada`).
```ts
// Público (telão): uma linha por rodada que a premiação cuida (acabou depois de ligada_em).
// [{ round_id, round_name, display_name, score }]. display_name e score nulos = carência,
// sem retirada ou cancelado (o letreiro some). Premiação desligada: nenhuma linha.
const { data: oficiais } = await supabase.rpc('get_official_winners')
// Só logado: os prêmios da própria conta no evento atual, o mais recente primeiro.
// [{ round_name, status, code, claim_deadline, delivered_at }]. code só vem quando vale.
const { data: meus } = await supabase.rpc('get_my_prize')
```
- Estados (`status`, snake_case): `avisado`, `prazo_estourou` (código ainda vale), `entregue`, `passou` (foi para outra conta), `recusado`, `cancelado`; `avisando`/`aviso_falhou` só quando houver canal de aviso (NEU-112).
- As tabelas da premiação (`premiacao_config`, `premiacao_rodadas`, `premios`, `premiacao_registro`) **não** são lidas pelo site: só pelas funções acima.
- **Painel de ops (`/operador`, NEU-168):** `op_painel()`, `op_validar_codigo(p_codigo)`, `op_acao(p_premio, p_acao, p_motivo?)` e `op_config(p_mudancas)`. Só para quem tem o e-mail confirmado na lista `operadores` (por SQL); outra conta recebe `42501`. Erro de negócio volta como `{"ok": false, "erro": "..."}` (em `op_acao`) e o contato já vem mascarado. Contrato completo no comentário da NEU-114 (21/10).

## 8.2 Links dos e-mails: "Parar de receber" e "Não vou poder" (NEU-112)
Os e-mails da premiação trazem links para `https://<site>/mensagens?t=<token>`. O token é `base64url(JSON).assinatura`, com o JSON `{ a: 'sair' | 'recusar', m: <id da mensagem>, exp: <epoch em s> }` (sem e-mail nem telefone). O site pode ler `a` para escolher o texto, mas **quem valida é a função**. A página **só age no clique**: antivírus de e-mail abrem os links sozinhos.
```ts
// Sem login e sem apikey: o token assinado é a prova. CORS liberado só para SITE_URL.
const r = await fetch(`${SUPABASE_URL}/functions/v1/message-actions`, {
  method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ t }),
})
// 200 { ok: true, acao: 'sair' }
// 200 { ok: true, acao: 'recusar', resultado: 'recusado' | 'ja_resolvido' | 'invalido' }
// 403 { erro: 'assinatura' } (link alterado ou vencido: sair vale 90 dias, recusar 2 dias)
// 404 { erro: 'nao_encontrada' } · 405 em GET · 500 { erro: 'falha_interna' }
```

## 9. Limitações honestas (para não perderem tempo)
- **Banco vazio até o edge gravar a 1ª corrida real.** Vocês conseguem montar UI, auth e queries agora; os dados aparecem quando uma corrida real fluir (e o usuário se cadastrar com o e-mail daquela corrida). Não há seed.
- **Ranking mostra só quem tem `display_name` + corridas finalizadas.** Fica vazio enquanto os jogadores não tiverem escolhido um nome e não tiverem finalizadas corridas; é comportamento esperado.
- **Confirmação de e-mail obrigatória** — no dev, confirmem usuários de teste pelo painel até a URL de redirect de vocês ser liberada.

---
*Dúvidas de schema: ver as migrations em `supabase/migrations/`. Contrato de escrita (edge→cloud): `../edge-service/docs/cloud-sync-contract.md`.*
