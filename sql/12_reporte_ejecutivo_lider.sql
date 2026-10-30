-- 12 · Reporte ejecutivo del líder (estado final de las migraciones 12 a 17 en Supabase)
-- Incluye: columna graficas, estado "enviando" contra doble envío, ventana configurable del reporte
-- y la vista v_reporte_lider (semáforo, KPIs, decisiones, SLA en riesgo, incidentes, resueltos).

alter table resumenes_diarios add column if not exists graficas jsonb;

-- Contra doble toque en "Confirmar escalamiento": abierto → enviando → en_revision → cerrado
do $$
declare c text;
begin
  select conname into c from pg_constraint
   where conrelid = 'escalamientos'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%en_revision%';
  if c is not null then execute format('alter table escalamientos drop constraint %I', c); end if;
end $$;
alter table escalamientos add constraint escalamientos_estado_check
  check (estado in ('abierto', 'enviando', 'en_revision', 'cerrado'));
comment on column escalamientos.estado is 'abierto → enviando (reservado por un toque de Confirmar; evita correos duplicados) → en_revision → cerrado';

-- Ventana del reporte en un solo lugar: null = acumulado; un número = últimas N horas.
create table if not exists config_reporte (
  id int primary key default 1 check (id = 1),
  ventana_horas int check (ventana_horas is null or ventana_horas > 0),
  actualizado_at timestamptz not null default now()
);
insert into config_reporte (id, ventana_horas) values (1, 24)
  on conflict (id) do nothing;
comment on table config_reporte is 'Ventana del reporte del líder. ventana_horas null = acumulado (todos los casos); 24 = operación diaria normal.';

create or replace function ventana_desde() returns timestamptz language sql stable as $$
  select case when c.ventana_horas is null then '-infinity'::timestamptz
              else now() - make_interval(hours => c.ventana_horas) end
  from config_reporte c where c.id = 1
$$;

create or replace function periodo_etiqueta() returns text language sql stable as $$
  select case when c.ventana_horas is null
              then 'acumulado desde ' || coalesce((select to_char(min(t.created_at) at time zone 'America/Bogota', 'DD/MM')
                                                   from tickets t where not t.es_set_prueba), 'el inicio')
              else 'últimas ' || c.ventana_horas || ' h' end
  from config_reporte c where c.id = 1
$$;

-- v_resumen_diario y v_graficas_diarias: el corte fijo de 24 h pasa a ventana_desde() y exponen el periodo
do $$
declare d text; patron text := '(now() - ''24:00:00''::interval)';
begin
  d := pg_get_viewdef('public.v_resumen_diario'::regclass);
  d := replace(d, patron, 'ventana_desde()');
  if position('AS periodo;' in d) = 0 then
    d := replace(d, 'FROM base) AS costo_usd_por_ticket_p1;', 'FROM base) AS costo_usd_por_ticket_p1, periodo_etiqueta() AS periodo;');
  end if;
  execute 'create or replace view public.v_resumen_diario as ' || d;

  d := pg_get_viewdef('public.v_graficas_diarias'::regclass);
  d := replace(d, patron, 'ventana_desde()');
  if position('''periodo''' in d) = 0 then
    d := replace(d, 'jsonb_build_object(''total'', count(*)', 'jsonb_build_object(''periodo'', periodo_etiqueta(), ''total'', count(*)');
  end if;
  execute 'create or replace view public.v_graficas_diarias as ' || d;
end $$;

create or replace view v_reporte_lider as
with vivos as (
  select t.id, t.numero_caso, t.cliente, t.pais, t.asunto, t.created_at,
         c.severidad, c.origen_falla, c.producto, c.codigo_motivo,
         r.id as respuesta_id, r.tipo as respuesta_tipo, r.estado as estado_resp,
         coalesce(r.texto_final, r.borrador) as borrador, r.revisado_at, r.enviado_at,
         e.id as escalamiento_id, e.estado as estado_esc, e.ficha,
         case c.severidad when 'P1' then interval '30 min' when 'P2' then interval '2 hours'
              when 'P3' then interval '24 hours' else interval '48 hours' end as limite
  from tickets t
  join lateral (select * from clasificaciones x where x.ticket_id = t.id order by x.created_at desc limit 1) c on true
  left join lateral (select * from respuestas x where x.ticket_id = t.id order by x.created_at desc limit 1) r on true
  left join lateral (select * from escalamientos x where x.ticket_id = t.id order by x.created_at desc limit 1) e on true
  where not t.es_set_prueba
),
pend as (
  select v.*, round(extract(epoch from (v.limite - (now() - v.created_at))) / 60) as min_restantes,
         (now() - v.created_at) > v.limite * 0.8 as en_riesgo
  from vivos v where v.respuesta_id is not null and coalesce(v.estado_resp, 'pendiente') = 'pendiente'
),
esc as (select v.* from vivos v where v.escalamiento_id is not null and v.estado_esc = 'abierto'),
h24 as (
  select v.*,
    case when coalesce(v.estado_resp, 'pendiente') <> 'pendiente'
         then (coalesce(v.revisado_at, now()) - v.created_at) <= v.limite
         else (now() - v.created_at) <= v.limite end as cumple
  from vivos v where v.created_at > ventana_desde()
),
res as (
  select v.*, round(extract(epoch from (v.enviado_at - v.created_at)) / 60) as min_respuesta,
         (v.enviado_at - v.created_at) <= v.limite as cumple_sla,
         case when v.estado_esc in ('en_revision', 'enviando') then 'en_ingenieria'
              when v.estado_esc = 'abierto' then 'escalamiento_por_confirmar'
              else 'cerrado' end as situacion
  from vivos v where v.enviado_at is not null and v.enviado_at > ventana_desde()
),
inc as (
  select i.firma, i.producto, i.pais, i.codigo_motivo as codigo,
         min(coalesce(i.inicio_at, i.created_at)) as desde, count(distinct i.id) as oleadas,
         array_agg(distinct cs.caso order by cs.caso) filter (where cs.caso is not null) as casos
  from incidentes i left join lateral unnest(i.casos) cs(caso) on true
  where i.estado = 'abierto'
  group by i.firma, i.producto, i.pais, i.codigo_motivo
),
dec as (
  select 'aprobar' as tipo, p.numero_caso, p.pais, p.severidad, p.cliente, p.respuesta_id::text as id,
         case when p.respuesta_tipo = 'comunicado' then 'Aprobar comunicado' else 'Aprobar respuesta' end as etiqueta,
         p.min_restantes, p.borrador as texto, p.asunto
  from pend p
  union all
  select 'escalar', s.numero_caso, s.pais, s.severidad, s.cliente, s.escalamiento_id::text,
         'Confirmar escalamiento', null, coalesce(s.ficha->>'titulo', s.asunto), s.asunto
  from esc s
),
k as (
  select (select count(*) from h24) as casos_24h,
         (select round(100.0 * count(*) filter (where cumple) / nullif(count(*), 0)) from h24) as sla_pct,
         (select count(*) from pend) as por_aprobar,
         (select count(*) from esc) as escalamientos_abiertos,
         (select count(*) from inc) as incidentes_abiertos,
         (select count(*) from pend where en_riesgo) as sla_en_riesgo,
         (select count(*) from pend where en_riesgo and severidad = 'P1') as p1_en_riesgo,
         (select count(*) from res) as resueltos_24h,
         (select count(*) from res where situacion = 'en_ingenieria') as en_ingenieria
)
select
  (now() at time zone 'America/Bogota') as generado_en,
  case when k.incidentes_abiertos > 0 or k.p1_en_riesgo > 0 then 'rojo'
       when k.sla_en_riesgo > 0 or k.escalamientos_abiertos > 0 then 'amarillo'
       else 'verde' end as semaforo,
  concat_ws(' y ',
    case when k.incidentes_abiertos = 1 then '1 incidente abierto' when k.incidentes_abiertos > 1 then k.incidentes_abiertos || ' incidentes abiertos' end,
    case when k.sla_en_riesgo = 1 then '1 SLA en riesgo' when k.sla_en_riesgo > 1 then k.sla_en_riesgo || ' SLA en riesgo' end,
    case when k.escalamientos_abiertos = 1 then '1 escalamiento por confirmar' when k.escalamientos_abiertos > 1 then k.escalamientos_abiertos || ' escalamientos por confirmar' end
  ) as motivo,
  jsonb_build_object('periodo', periodo_etiqueta(), 'casos_24h', k.casos_24h, 'sla_pct', coalesce(k.sla_pct, 100), 'por_aprobar', k.por_aprobar,
    'escalamientos_abiertos', k.escalamientos_abiertos, 'incidentes_abiertos', k.incidentes_abiertos, 'sla_en_riesgo', k.sla_en_riesgo,
    'resueltos_24h', k.resueltos_24h, 'en_ingenieria', k.en_ingenieria) as kpis,
  (select coalesce(jsonb_agg(to_jsonb(d) order by d.orden, d.min_restantes nulls last, d.numero_caso), '[]'::jsonb)
     from (select dec.*, case when dec.severidad = 'P1' then 0 when dec.min_restantes is not null and dec.min_restantes < 60 then 1 when dec.tipo = 'escalar' then 2 else 3 end as orden from dec) d) as decisiones,
  (select coalesce(jsonb_agg(jsonb_build_object('caso', p.numero_caso, 'pais', p.pais, 'severidad', p.severidad, 'cliente', p.cliente,
      'tipo', p.respuesta_tipo, 'min_restantes', p.min_restantes, 'respuesta_id', p.respuesta_id, 'texto', p.borrador, 'asunto', p.asunto) order by p.min_restantes), '[]'::jsonb)
     from pend p where p.en_riesgo) as sla_riesgo,
  (select coalesce(jsonb_agg(jsonb_build_object('firma', i.firma, 'producto', i.producto, 'pais', i.pais, 'codigo', i.codigo,
      'casos', i.casos, 'desde', to_char(i.desde at time zone 'America/Bogota', 'DD/MM HH24:MI'), 'oleadas', i.oleadas,
      'accion', case when i.firma = 'fuente_externa' then 'Confirmar en status.truora.com y comunicar; no escalar' else 'Escalar a Ingeniería con la ficha' end) order by i.desde), '[]'::jsonb)
     from inc i) as incidentes,
  (select patrones from v_resumen_diario) as patrones,
  (select jsonb_build_object('texto', rd.texto, 'graficas', rd.graficas, 'creado', to_char(rd.created_at at time zone 'America/Bogota', 'DD/MM HH24:MI'))
     from resumenes_diarios rd order by rd.created_at desc limit 1) as ultimo_resumen,
  (select coalesce(jsonb_agg(jsonb_build_object('caso', x.numero_caso, 'pais', x.pais, 'severidad', x.severidad, 'cliente', x.cliente,
      'asunto', x.asunto, 'tipo', x.respuesta_tipo, 'min_respuesta', x.min_respuesta, 'cumple_sla', x.cumple_sla,
      'situacion', x.situacion, 'enviado', to_char(x.enviado_at at time zone 'America/Bogota', 'DD/MM HH24:MI')) order by x.enviado_at desc), '[]'::jsonb)
     from res x) as resueltos
from k;
