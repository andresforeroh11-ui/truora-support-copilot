-- =====================================================================
-- Truora · Copiloto de Triage y Escalamiento — Esquema Supabase
-- Pegar completo en Supabase > SQL Editor > Run
-- 8 tablas + 1 vista de métricas. Solo datos sintéticos.
-- =====================================================================

create extension if not exists pgcrypto;

-- 1. TICKETS: entrada del flujo (formulario de n8n)
create table if not exists tickets (
  id                  uuid primary key default gen_random_uuid(),
  created_at          timestamptz not null default now(),
  ticket_ref          text unique,                 -- ej. T01..T40 en el set de prueba
  cliente             text,                        -- cliente ficticio
  pais                text check (pais in ('MX','BR','CO','CL','PE','otro','desconocido')),
  canal               text default 'formulario',
  asunto              text,
  cuerpo              text not null,
  es_set_prueba       boolean not null default false,
  -- Etiquetas "verdad" puestas a mano por Andrés (solo set de evaluación)
  etiqueta_severidad  text check (etiqueta_severidad in ('P1','P2','P3','P4')),
  etiqueta_origen     text check (etiqueta_origen in ('truora','fuente_externa_gobierno','meta_whatsapp',
                                  'integracion_cliente','usuario_final','no_aplica','indeterminado'))
);

-- 2. CLASIFICACIONES: salida de P1
create table if not exists clasificaciones (
  id                     uuid primary key default gen_random_uuid(),
  created_at             timestamptz not null default now(),
  ticket_id              uuid not null references tickets(id) on delete cascade,
  modelo                 text,
  prompt_version         text default 'P1-v2',
  producto               text,
  pais                   text,
  ambiente               text,
  tipo                   text,
  origen_falla           text,
  codigo_motivo          text,
  severidad              text check (severidad in ('P1','P2','P3','P4')),
  confianza              numeric(3,2),
  justificacion          text,
  datos_faltantes        jsonb default '[]'::jsonb,
  requiere_escalamiento  boolean,
  accion_sugerida        text check (accion_sugerida in ('escalar_ingenieria','comunicado_proactivo',
                                     'responder_con_kb','pedir_datos')),
  json_crudo             jsonb,                    -- respuesta completa del modelo
  json_valido            boolean default true,
  error                  text,
  latencia_ms            integer,
  tokens_entrada         integer,
  tokens_salida          integer,
  costo_usd              numeric(10,6)
);

-- 3. RESPUESTAS: borradores de P2 (respuesta al cliente o comunicado proactivo)
create table if not exists respuestas (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  ticket_id         uuid not null references tickets(id) on delete cascade,
  clasificacion_id  uuid references clasificaciones(id) on delete set null,
  tipo              text check (tipo in ('respuesta','comunicado')) default 'respuesta',
  borrador          text not null,
  estado            text check (estado in ('pendiente','aprobado','editado','rechazado')) default 'pendiente',
  texto_final       text,
  revisado_at       timestamptz
);

-- 4. ESCALAMIENTOS: fichas de P3 para Ingeniería
create table if not exists escalamientos (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  ticket_id         uuid not null references tickets(id) on delete cascade,
  clasificacion_id  uuid references clasificaciones(id) on delete set null,
  ficha             jsonb not null,               -- formato fijo de P3
  hipotesis         text,
  estado            text check (estado in ('abierto','en_revision','cerrado')) default 'abierto'
);

-- 5. INCIDENTES: alertas del Workflow B
create table if not exists incidentes (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),
  producto          text,
  pais              text,
  firma             text check (firma in ('fuente_externa','plataforma')),
  codigo_motivo     text,
  ticket_ids        uuid[] not null,
  mensaje_alerta    text,
  estado            text check (estado in ('abierto','cerrado')) default 'abierto'
);

-- 6. KB_ARTICULOS: 6 artículos de conocimiento
create table if not exists kb_articulos (
  id            bigint generated always as identity primary key,
  slug          text unique not null,             -- ej. fuente-externa-caida
  titulo        text not null,
  contenido     text not null,
  producto      text,
  origen_falla  text,
  fuente_url    text
);

-- 7. KB_MOTIVOS: catálogo de motivos de rechazo (importar claude/kb_motivos.csv)
--    Columnas con los mismos nombres del CSV para importarlo directo.
create table if not exists kb_motivos (
  id                       bigint generated always as identity primary key,
  codigo                   text not null,
  tipo                     text,                  -- declined | expired
  validador                text,                  -- document, face, front_end...
  descripcion_en           text,
  clasificacion            text,
  clasificacion_es         text,
  paises                   text,
  dispara_revision_manual  text,
  origen_falla_sugerido    text,
  fuente                   text,
  explicacion_es           text,
  accion_usuario_final     text,
  accion_cliente           text,
  escalar_si               text,
  nota_tono                text,
  unique (codigo, tipo, validador)
);
create index if not exists kb_motivos_codigo_idx on kb_motivos (codigo);

-- 8. EVALUACIONES: una fila por ticket por corrida
create table if not exists evaluaciones (
  id                         uuid primary key default gen_random_uuid(),
  created_at                 timestamptz not null default now(),
  corrida                    integer not null,     -- 1, 2...
  prompt_version             text,
  ticket_id                  uuid not null references tickets(id) on delete cascade,
  clasificacion_id           uuid references clasificaciones(id) on delete set null,
  severidad_esperada         text,
  severidad_obtenida         text,
  origen_esperado            text,
  origen_obtenido            text,
  acierto_severidad          boolean generated always as (severidad_esperada = severidad_obtenida) stored,
  acierto_origen             boolean generated always as (origen_esperado = origen_obtenido) stored,
  p1_no_detectado            boolean generated always as (severidad_esperada = 'P1' and severidad_obtenida <> 'P1') stored,
  escalamiento_innecesario   boolean,             -- escaló y el origen etiquetado no es truora
  borrador_usable            boolean              -- lo marcas tú al revisar
);

-- VISTA: métricas por corrida (para el video y las notas)
create or replace view v_metricas_corrida as
select
  corrida,
  max(prompt_version)                                                       as prompt_version,
  count(*)                                                                  as tickets,
  round(100.0 * avg(acierto_severidad::int), 1)                             as precision_severidad_pct,
  round(100.0 * avg(acierto_origen::int), 1)                                as precision_origen_pct,
  sum(p1_no_detectado::int)                                                 as p1_no_detectados,
  sum(coalesce(escalamiento_innecesario, false)::int)                       as escalamientos_innecesarios,
  round(100.0 * avg(borrador_usable::int) filter (where borrador_usable is not null), 1) as borradores_usables_pct
from evaluaciones
group by corrida
order by corrida;

-- SEGURIDAD: RLS activo sin políticas = la clave pública (anon) no puede leer nada.
-- n8n usa la service_role key, que no se ve afectada por RLS.
alter table tickets          enable row level security;
alter table clasificaciones  enable row level security;
alter table respuestas       enable row level security;
alter table escalamientos    enable row level security;
alter table incidentes       enable row level security;
alter table kb_articulos     enable row level security;
alter table kb_motivos       enable row level security;
alter table evaluaciones     enable row level security;
