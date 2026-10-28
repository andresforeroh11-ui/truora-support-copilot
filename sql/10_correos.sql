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

-- v_caso_detalle (versión final): ver la migración aplicada en Supabase "correos_enviados_y_destinatarios".
