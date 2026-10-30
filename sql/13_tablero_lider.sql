-- 13 · Tablero del líder: matriz severidad × estado de SLA (estado final de las migraciones de tablero en Supabase)
-- Lo usan el flujo F (página web) y el flujo D (foto del reporte en Telegram y tabla del correo).

-- Un renglón por caso: quién tiene el siguiente paso, qué está pendiente y estado de SLA de primera respuesta.
create or replace view public.v_tablero_casos as
with base as (
  select t.id as ticket_id, t.numero_caso, t.cliente, t.pais, t.asunto, t.created_at,
         c.severidad, c.origen_falla, c.producto, c.codigo_motivo, c.accion_sugerida,
         r.id as respuesta_id, r.tipo as resp_tipo, r.estado as resp_estado,
         coalesce(r.enviado_at, case when r.estado in ('aprobado','editado') then r.revisado_at end) as resp_at,
         e.id as escalamiento_id, e.estado as esc_estado,
         case c.severidad when 'P1' then interval '30 minutes' when 'P2' then interval '2 hours'
                          when 'P3' then interval '24 hours' else interval '48 hours' end as limite
  from tickets t
  join lateral (select * from clasificaciones x where x.ticket_id = t.id order by x.created_at desc limit 1) c on true
  left join lateral (select * from respuestas x where x.ticket_id = t.id order by x.created_at desc limit 1) r on true
  left join lateral (select * from escalamientos x where x.ticket_id = t.id order by x.created_at desc limit 1) e on true
  where not t.es_set_prueba
), est as (
  select b.*,
    case
      when b.resp_at is null then 'lider'
      when b.esc_estado = 'abierto' then 'lider'
      when b.esc_estado in ('enviando','en_revision') then 'ingenieria'
      when b.accion_sugerida = 'pedir_datos' then 'cliente'
    end as responsable,
    case
      when b.resp_at is null and b.resp_estado = 'pendiente' and b.resp_tipo = 'comunicado' then 'Aprobar comunicado'
      when b.resp_at is null and b.resp_estado = 'pendiente' then 'Aprobar respuesta'
      when b.resp_at is null then 'Revisar caso sin borrador'
      when b.esc_estado = 'abierto' then 'Confirmar escalamiento'
      when b.esc_estado in ('enviando','en_revision') then 'Diagnóstico en Ingeniería'
      when b.accion_sugerida = 'pedir_datos' then 'Enviar datos pedidos'
    end as pendiente
  from base b
)
select e.*,
  (e.responsable is not null) as abierto,
  case
    when e.responsable is not null then
      case
        when e.resp_at is not null then case when e.resp_at - e.created_at <= e.limite then 'en_tiempo' else 'vencido' end
        when now() - e.created_at > e.limite then 'vencido'
        when now() - e.created_at > e.limite * 0.8 then 'en_riesgo'
        else 'en_tiempo'
      end
    else case when e.resp_at - e.created_at <= e.limite then 'en_sla' else 'fuera_sla' end
  end as estado_sla,
  round(extract(epoch from (e.limite - (coalesce(e.resp_at, now()) - e.created_at))) / 60) as min_restantes,
  (e.responsable is not null or e.resp_at > ventana_desde()) as en_tablero
from est e;

comment on view public.v_tablero_casos is 'Tablero B: un renglón por caso con responsable del siguiente paso, pendiente y estado de SLA de primera respuesta. min_restantes negativo = minutos pasados del límite.';

create or replace view public.v_tablero_b_base as
with u as (
  select * from public.v_tablero_casos
  where abierto or resp_at > ventana_desde()
), sev as (
  select s.sev,
    count(*) filter (where u.abierto and u.estado_sla = 'en_tiempo') as ab_tiempo,
    count(*) filter (where u.abierto and u.estado_sla = 'en_riesgo') as ab_riesgo,
    count(*) filter (where u.abierto and u.estado_sla = 'vencido')  as ab_vencido,
    count(*) filter (where not u.abierto and u.estado_sla = 'en_sla')    as ce_sla,
    count(*) filter (where not u.abierto and u.estado_sla = 'fuera_sla') as ce_fuera
  from (values ('P1'),('P2'),('P3'),('P4')) s(sev)
  left join u on u.severidad = s.sev
  group by s.sev
), tot as (
  select sum(ab_tiempo)::int ab_tiempo, sum(ab_riesgo)::int ab_riesgo, sum(ab_vencido)::int ab_vencido,
         sum(ce_sla)::int ce_sla, sum(ce_fuera)::int ce_fuera from sev
), k as (
  select t.*, (ab_tiempo + ab_riesgo + ab_vencido) as abiertos, (ce_sla + ce_fuera) as cerrados,
         (ab_vencido + ce_fuera) as vencidos from tot t
)
select
  (now() at time zone 'America/Bogota') as generado_en,
  periodo_etiqueta() as periodo,
  jsonb_build_object(
    'abiertos', k.abiertos, 'cerrados', k.cerrados, 'total', k.abiertos + k.cerrados,
    'pct_abiertos', round(100.0 * k.abiertos / nullif(k.abiertos + k.cerrados, 0)),
    'pct_cerrados', round(100.0 * k.cerrados / nullif(k.abiertos + k.cerrados, 0)),
    'sla_cumplido_pct', round(100.0 * k.ce_sla / nullif(k.cerrados, 0)),
    'vencidos', k.vencidos,
    'pct_vencidos', round(100.0 * k.vencidos / nullif(k.abiertos + k.cerrados, 0)),
    'vencidos_abiertos', k.ab_vencido, 'vencidos_cerrados', k.ce_fuera,
    'pct_venc_abiertos', round(100.0 * k.ab_vencido / nullif(k.vencidos, 0)),
    'pct_venc_cerrados', round(100.0 * k.ce_fuera / nullif(k.vencidos, 0))
  ) as kpis,
  (select jsonb_agg(jsonb_build_object('sev', sev, 'ab_tiempo', ab_tiempo, 'ab_riesgo', ab_riesgo, 'ab_vencido', ab_vencido,
                                       'ce_sla', ce_sla, 'ce_fuera', ce_fuera) order by sev) from sev) as matriz,
  jsonb_build_object(
    'ab_tiempo',  jsonb_build_object('n', k.ab_tiempo,  'pct', round(100.0 * k.ab_tiempo  / nullif(k.abiertos, 0))),
    'ab_riesgo',  jsonb_build_object('n', k.ab_riesgo,  'pct', round(100.0 * k.ab_riesgo  / nullif(k.abiertos, 0))),
    'ab_vencido', jsonb_build_object('n', k.ab_vencido, 'pct', round(100.0 * k.ab_vencido / nullif(k.abiertos, 0))),
    'ce_sla',     jsonb_build_object('n', k.ce_sla,     'pct', round(100.0 * k.ce_sla     / nullif(k.cerrados, 0))),
    'ce_fuera',   jsonb_build_object('n', k.ce_fuera,   'pct', round(100.0 * k.ce_fuera   / nullif(k.cerrados, 0)))
  ) as totales,
  (select coalesce(jsonb_agg(jsonb_build_object('caso', numero_caso, 'sev', severidad, 'pais', pais, 'asunto', asunto,
                                                'pendiente', pendiente, 'estado', estado_sla, 'min', min_restantes)
                             order by (estado_sla = 'vencido') desc, min_restantes), '[]'::jsonb)
     from u where abierto and estado_sla in ('vencido','en_riesgo')) as por_atender,
  (select coalesce(jsonb_agg(jsonb_build_object('responsable', g.responsable, 'n', g.n, 'acciones', g.acciones)
                             order by array_position(array['lider','cliente','ingenieria'], g.responsable)), '[]'::jsonb)
     from (select responsable, count(*) n,
                  (select jsonb_agg(jsonb_build_object('pendiente', a.pendiente, 'n', a.n) order by a.n desc)
                     from (select pendiente, count(*) n from u u2 where u2.abierto and u2.responsable = u1.responsable group by pendiente) a) acciones
           from u u1 where abierto group by responsable) g) as pendientes
from k;

-- SLA de primera respuesta: sobre TODOS los casos ya respondidos (abiertos o cerrados).
-- Un caso respondido a tiempo cumple su SLA de respuesta aunque siga en Ingeniería.
create or replace view public.v_tablero_b as
select b.generado_en, b.periodo,
  b.kpis || jsonb_build_object(
    'respondidos', r.respondidos,
    'respondidos_a_tiempo', r.a_tiempo,
    'sla_respuesta_pct', round(100.0 * r.a_tiempo / nullif(r.respondidos, 0)),
    'sin_responder', r.sin_responder
  ) as kpis,
  b.matriz, b.totales, b.por_atender, b.pendientes
from public.v_tablero_b_base b
cross join (
  select count(*) filter (where resp_at is not null) as respondidos,
         count(*) filter (where resp_at is not null and resp_at - created_at <= limite) as a_tiempo,
         count(*) filter (where resp_at is null) as sin_responder
  from public.v_tablero_casos
  where abierto or resp_at > ventana_desde()
) r;

comment on view public.v_tablero_b is 'Tablero B del líder: matriz severidad × estado de SLA, totales con %, vencidos, abiertos por atender, pendientes por responsable y SLA de primera respuesta.';
