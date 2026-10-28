-- =====================================================================
-- 10 · Correos: destinatarios, registro de envíos y marcas de envío
-- - destinatarios_correo: a quién va cada tipo de correo (cliente, ingenieria, lider).
--   DEMO: los clientes son ficticios, así que el rol 'cliente' apunta a un buzón de prueba.
-- - correos_enviados: un registro por correo (enviado o con error), con el id de Gmail.
-- - respuestas.enviado_at y escalamientos.confirmado_at: cuándo salió el correo.
-- - v_caso_detalle: agrega ticket_id, respuesta_id, escalamiento_id, fechas de envío y la lista de correos.
-- =====================================================================

create table if not exists destinatarios_correo (
  rol     text primary key check (rol in ('cliente','ingenieria','lider')),
  correo  text not null,
  nota    text
);
-- Cambia los correos por los tuyos:
insert into destinatarios_correo (rol, correo, nota) values
  ('cliente',    'TU_CORREO_DE_PRUEBA', 'Demo: en producción sería el contacto del cliente en el help desk'),
  ('ingenieria', 'TU_CORREO_DE_PRUEBA', 'Demo: en producción, la lista o el canal de guardia de Ingeniería'),
  ('lider',      'TU_CORREO_DE_PRUEBA', 'Líder de soporte: recibe el resumen diario')
on conflict (rol) do nothing;

create table if not exists correos_enviados (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  tipo                text not null check (tipo in ('respuesta_cliente','comunicado_cliente','escalamiento_ingenieria','resumen_diario')),
  ticket_id           uuid references tickets(id) on delete set null,
  numero_caso         bigint,
  respuesta_id        uuid references respuestas(id) on delete set null,
  escalamiento_id     uuid references escalamientos(id) on delete set null,
  destinatario        text not null,
  destinatario_real   text,
  asunto              text not null,
  cuerpo              text,
  estado              text not null check (estado in ('enviado','error')),
  gmail_id            text,
  error               text
);
create index if not exists correos_enviados_ticket_idx on correos_enviados (ticket_id);

alter table respuestas    add column if not exists enviado_at    timestamptz;
alter table escalamientos add column if not exists confirmado_at timestamptz;

alter table destinatarios_correo enable row level security;
alter table correos_enviados     enable row level security;

-- v_caso_detalle (versión final): agrega ids, fechas de envío y la lista de correos del caso
create or replace view v_caso_detalle with (security_invoker = true) as
select t.numero_caso, t.ticket_ref, t.created_at as recibido_at, t.cliente, t.pais, t.canal, t.asunto, t.cuerpo,
       c.severidad, c.origen_falla, c.producto, c.ambiente, c.codigo_motivo, c.accion_sugerida,
       c.requiere_escalamiento, c.justificacion, c.datos_faltantes, c.confianza, c.created_at as clasificado_at,
       r.tipo as respuesta_tipo, r.estado as respuesta_estado, r.borrador, r.texto_final, r.revisado_at,
       e.estado as escalamiento_estado, e.hipotesis, e.ficha, e.created_at as escalado_at,
       i.incidente,
       t.id as ticket_id, r.id as respuesta_id, e.id as escalamiento_id,
       r.enviado_at as correo_cliente_enviado_at, e.confirmado_at as correo_ingenieria_enviado_at,
       (select coalesce(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'estado', m.estado, 'destinatario', m.destinatario, 'enviado_at', m.created_at) order by m.created_at), '[]'::jsonb)
        from correos_enviados m where m.ticket_id = t.id) as correos
from tickets t
left join lateral (select * from clasificaciones x where x.ticket_id = t.id order by x.created_at desc limit 1) c on true
left join lateral (select * from respuestas x where x.ticket_id = t.id order by x.created_at desc limit 1) r on true
left join lateral (select * from escalamientos x where x.ticket_id = t.id order by x.created_at desc limit 1) e on true
left join lateral (
  select jsonb_build_object('firma', x.firma, 'estado', x.estado, 'detectado_at', x.created_at,
                            'inicio_at', x.inicio_at, 'casos', x.casos, 'codigo_motivo', x.codigo_motivo) as incidente
  from incidentes x where t.id = any (x.ticket_ids) order by x.created_at desc limit 1) i on true;
