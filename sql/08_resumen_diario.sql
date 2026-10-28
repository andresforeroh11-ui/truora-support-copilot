-- Vista con las métricas de las últimas 24 h (solo tickets reales) y tabla de resúmenes.
-- Precio de referencia gpt-4o-mini (docs de OpenAI, oct 2026): USD 0,15 / 1M tokens de entrada y 0,60 / 1M de salida.
create table if not exists resumenes_diarios (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  metricas jsonb not null,
  texto text
);
alter table resumenes_diarios enable row level security;

create or replace view v_resumen_diario with (security_invoker = true) as
with base as (
  select t.id ticket_id, t.cliente, t.pais, t.asunto, t.created_at,
         c.severidad, c.origen_falla, c.producto, c.codigo_motivo, c.accion_sugerida, c.requiere_escalamiento,
         c.latencia_ms, c.tokens_entrada, c.tokens_salida, r.estado estado_respuesta
  from tickets t
  join clasificaciones c on c.ticket_id = t.id
  left join respuestas r on r.ticket_id = t.id
  where not t.es_set_prueba and t.created_at > now() - interval '24 hours'
),
sla as (
  select *, case severidad when 'P1' then interval '30 minutes' when 'P2' then interval '2 hours'
                           when 'P3' then interval '24 hours' else interval '48 hours' end limite
  from base
)
select
  now() at time zone 'America/Bogota' as generado_en,
  (select count(*) from base) as tickets_24h,
  (select coalesce(jsonb_object_agg(severidad, n), '{}') from (select severidad, count(*) n from base group by 1) x) as por_severidad,
  (select coalesce(jsonb_object_agg(origen_falla, n), '{}') from (select origen_falla, count(*) n from base group by 1) x) as por_origen,
  (select count(*) from base where requiere_escalamiento) as escalados_ingenieria,
  (select round(100.0 * avg((accion_sugerida in ('responder_con_kb','comunicado_proactivo'))::int), 1) from base) as pct_resoluble_sin_escalar,
  (select coalesce(jsonb_agg(jsonb_build_object('cliente', cliente, 'pais', pais, 'severidad', severidad, 'asunto', asunto,
          'minutos_abierto', round(extract(epoch from now() - created_at) / 60), 'limite_min', extract(epoch from limite) / 60)
          order by severidad), '[]')
     from sla where coalesce(estado_respuesta, 'pendiente') = 'pendiente' and now() - created_at > limite * 0.8) as sla_en_riesgo,
  (select coalesce(jsonb_agg(jsonb_build_object('firma', firma, 'producto', producto, 'pais', pais, 'tickets', array_length(ticket_ids, 1), 'codigo', codigo_motivo)), '[]')
     from incidentes where created_at > now() - interval '24 hours') as incidentes,
  (select coalesce(jsonb_agg(jsonb_build_object('patron', producto || ' · ' || origen_falla || coalesce(' · ' || codigo_motivo, ''), 'tickets', n) order by n desc), '[]')
     from (select producto, origen_falla, codigo_motivo, count(*) n from base group by 1,2,3 having count(*) >= 2) x) as patrones,
  (select coalesce(jsonb_object_agg(estado, n), '{}') from (select estado, count(*) n from respuestas r join base b on b.ticket_id = r.ticket_id group by 1) x) as borradores,
  (select round(100.0 * count(*) filter (where estado = 'aprobado') / nullif(count(*) filter (where estado in ('aprobado','editado','rechazado')), 0), 1)
     from respuestas r join base b on b.ticket_id = r.ticket_id) as pct_borradores_sin_edicion,
  (select round(avg(latencia_ms) / 1000.0, 1) from base) as seg_promedio_clasificacion,
  (select round((sum(tokens_entrada) * 0.15 + sum(tokens_salida) * 0.60) / 1e6 / nullif(count(*), 0), 5) from base) as costo_usd_por_ticket_p1;
