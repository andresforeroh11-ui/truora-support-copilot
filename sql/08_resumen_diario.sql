-- Vista con las métricas de las últimas 24 h (solo tickets reales) y tabla de resúmenes.
-- Precio de referencia gpt-4o-mini (docs de OpenAI, oct 2026): USD 0,15 / 1M tokens de entrada y 0,60 / 1M de salida.
-- Definición completa aplicada en Supabase como migración `resumen_diario`; ver el proyecto para el texto exacto.
create table if not exists resumenes_diarios (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  metricas jsonb not null,
  texto text
);
alter table resumenes_diarios enable row level security;
