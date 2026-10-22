-- NEU-112 (complemento, pedido na revisao do #19): o e-mail "voce venceu" (texto 2 da NEU-165).
-- Quando um premio da NEU-167 esta avisado e dentro do prazo, enfileira 1 e-mail na caixa de
-- saida para o e-mail confirmado da conta. So LE premios/premiacao_config: nao muda a 167/168.
-- O "Nao vou poder" vem no rodape, pela send-messages. Os outros avisos (faltam 10 min, lembrete,
-- prazo passou) seguem na NEU-169.
-- Volta: supabase/rollbacks/20261022093000_aviso_vencedor.down.sql.
--
-- Em prod, depois da migration (so com o ok do Pedro):
--   agendar: select cron.schedule('avisos-premio', '* * * * *', $$select public.avisos_premio_tick()$$);
--   ligar o envio do tipo: update public.mensagens_config
--     set tipos_ligados = array(select distinct unnest(tipos_ligados || array['premio_venceu']));
--   Voltar atras (leve): select cron.unschedule('avisos-premio');

-- Roda com a premiacao ligada e sem pausa geral. A chave (premio + canal) garante um aviso por
-- vez de premio: quando o premio passa, o proximo ganha o dele (premio novo, chave nova), e o
-- aviso pendente do anterior e cancelado pelo mensagens_preparar.
create function public.avisos_premio_tick(p_agora timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg       premiacao_config;
  p         record;
  v_destino text;
  v_avisos  int := 0;
  v_sem     int := 0;
  v_erros   int := 0;
begin
  select * into cfg from premiacao_config;
  if not cfg.premiacao_ligada then
    return jsonb_build_object('rodou', false, 'motivo', 'desligada');
  end if;
  if cfg.pausa_geral then
    return jsonb_build_object('rodou', false, 'motivo', 'pausa_geral');
  end if;

  for p in
    select pr.id, pr.round_id, pr.user_id, pr.display_name, pr.code, pr.prazo, w.name::text as rodada
    from premios pr
    join ranking_windows w on w.id = pr.round_id
    where pr.status = 'avisado'
      and pr.evento = cfg.evento_atual
      and pr.code is not null
      and pr.prazo > p_agora
      and not exists (select 1 from mensagens m where m.chave = 'premio_venceu:' || pr.id || ':email')
  loop
    begin
      -- So o e-mail confirmado da conta recebe o codigo.
      v_destino := mensagens_destino_email(p.user_id, null);
      if v_destino is null then
        v_sem := v_sem + 1;
        continue;
      end if;
      perform mensagem_enfileirar(
        'premio_venceu', 'email', v_destino, 'premio_venceu:' || p.id || ':email', p.prazo,
        'Você venceu a ' || p.rodada || ' do NeuroRace!',
        'Você venceu a ' || p.rodada || ' do NeuroRace, ' || p.display_name || '! Venha ao estande até '
          || to_char(p.prazo at time zone 'America/Sao_Paulo', 'HH24:MI') || ' e mostre o código ' || p.code || '.',
        null, p.user_id, null, p.id, p.round_id, p_agora);
      v_avisos := v_avisos + 1;
    exception when others then
      v_erros := v_erros + 1;
      raise warning 'avisos_premio_tick: premio % (%)', p.id, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('rodou', true, 'avisos', v_avisos, 'sem_contato', v_sem, 'erros', v_erros);
end;
$$;

revoke all on function public.avisos_premio_tick(timestamptz) from public, anon, authenticated;
grant execute on function public.avisos_premio_tick(timestamptz) to service_role;
