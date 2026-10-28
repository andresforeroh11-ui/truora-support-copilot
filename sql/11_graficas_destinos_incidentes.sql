-- 11 · Cambios del 28 oct: gráficas del resumen, gestión de casos, destino de patrones,
--      incidentes agrupados por oleadas y prompt P4 v2/v3.
-- Correr después de 01-10. Es idempotente (create or replace / on conflict).

-- v_graficas_diarias: Conteos para las 4 gráficas del resumen diario: origen x severidad, SLA por severidad, tendencia de 7 días y gestión de casos (base de conocimiento vs interna). Solo agregados, sin datos personales.
create or replace view public.v_graficas_diarias with (security_invoker = on) as
WITH base AS (
         SELECT t.id,
            t.numero_caso,
            t.created_at,
            c.severidad,
            c.origen_falla,
            c.requiere_escalamiento,
            c.accion_sugerida,
            r.estado AS estado_resp,
            r.revisado_at,
            e.estado AS estado_esc,
                CASE c.severidad
                    WHEN 'P1'::text THEN '00:30:00'::interval
                    WHEN 'P2'::text THEN '02:00:00'::interval
                    WHEN 'P3'::text THEN '24:00:00'::interval
                    ELSE '48:00:00'::interval
                END AS limite
           FROM tickets t
             JOIN LATERAL ( SELECT x.id,
                    x.created_at,
                    x.ticket_id,
                    x.modelo,
                    x.prompt_version,
                    x.producto,
                    x.pais,
                    x.ambiente,
                    x.tipo,
                    x.origen_falla,
                    x.codigo_motivo,
                    x.severidad,
                    x.confianza,
                    x.justificacion,
                    x.datos_faltantes,
                    x.requiere_escalamiento,
                    x.accion_sugerida,
                    x.json_crudo,
                    x.json_valido,
                    x.error,
                    x.latencia_ms,
                    x.tokens_entrada,
                    x.tokens_salida,
                    x.costo_usd
                   FROM clasificaciones x
                  WHERE x.ticket_id = t.id
                  ORDER BY x.created_at DESC
                 LIMIT 1) c ON true
             LEFT JOIN LATERAL ( SELECT x.id,
                    x.created_at,
                    x.ticket_id,
                    x.clasificacion_id,
                    x.tipo,
                    x.borrador,
                    x.estado,
                    x.texto_final,
                    x.revisado_at,
                    x.enviado_at
                   FROM respuestas x
                  WHERE x.ticket_id = t.id
                  ORDER BY x.created_at DESC
                 LIMIT 1) r ON true
             LEFT JOIN LATERAL ( SELECT x.id,
                    x.created_at,
                    x.ticket_id,
                    x.clasificacion_id,
                    x.ficha,
                    x.hipotesis,
                    x.estado,
                    x.confirmado_at
                   FROM escalamientos x
                  WHERE x.ticket_id = t.id
                  ORDER BY x.created_at DESC
                 LIMIT 1) e ON true
          WHERE NOT t.es_set_prueba
        ), h24 AS (
         SELECT base.id,
            base.numero_caso,
            base.created_at,
            base.severidad,
            base.origen_falla,
            base.requiere_escalamiento,
            base.accion_sugerida,
            base.estado_resp,
            base.revisado_at,
            base.estado_esc,
            base.limite
           FROM base
          WHERE base.created_at > (now() - '24:00:00'::interval)
        ), sla AS (
         SELECT h24.severidad,
                CASE
                    WHEN COALESCE(h24.estado_resp, 'pendiente'::text) <> 'pendiente'::text THEN
                    CASE
                        WHEN (COALESCE(h24.revisado_at, now()) - h24.created_at) <= h24.limite THEN 'en_plazo'::text
                        ELSE 'vencido'::text
                    END
                    WHEN (now() - h24.created_at) > h24.limite THEN 'vencido'::text
                    WHEN (now() - h24.created_at) > (h24.limite * 0.8::double precision) THEN 'en_riesgo'::text
                    ELSE 'en_plazo'::text
                END AS estado
           FROM h24
        ), gest AS (
         SELECT h24.numero_caso,
                CASE
                    WHEN h24.requiere_escalamiento OR h24.accion_sugerida = 'escalar_ingenieria'::text THEN 'interno_ingenieria'::text
                    WHEN h24.accion_sugerida = 'pedir_datos'::text THEN 'interno_datos'::text
                    WHEN h24.estado_resp = 'rechazado'::text THEN 'interno_manual'::text
                    WHEN h24.estado_resp = ANY (ARRAY['aprobado'::text, 'editado'::text]) THEN 'kb_resuelto'::text
                    ELSE 'kb_por_aprobar'::text
                END AS bucket
           FROM h24
        )
 SELECT (now() AT TIME ZONE 'America/Bogota'::text) AS generado_en,
    ( SELECT count(*) AS count
           FROM h24) AS tickets_24h,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('origen', x.o, 'P1', x.p1, 'P2', x.p2, 'P3', x.p3, 'P4', x.p4) ORDER BY x.total DESC), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT COALESCE(h24.origen_falla, 'sin_clasificar'::text) AS o,
                    count(*) AS total,
                    count(*) FILTER (WHERE h24.severidad = 'P1'::text) AS p1,
                    count(*) FILTER (WHERE h24.severidad = 'P2'::text) AS p2,
                    count(*) FILTER (WHERE h24.severidad = 'P3'::text) AS p3,
                    count(*) FILTER (WHERE h24.severidad = 'P4'::text) AS p4
                   FROM h24
                  GROUP BY (COALESCE(h24.origen_falla, 'sin_clasificar'::text))) x) AS origen_severidad,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('severidad', x.s, 'en_plazo', x.a, 'en_riesgo', x.b, 'vencido', x.v) ORDER BY x.s), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT sla.severidad AS s,
                    count(*) FILTER (WHERE sla.estado = 'en_plazo'::text) AS a,
                    count(*) FILTER (WHERE sla.estado = 'en_riesgo'::text) AS b,
                    count(*) FILTER (WHERE sla.estado = 'vencido'::text) AS v
                   FROM sla
                  GROUP BY sla.severidad) x) AS sla_por_severidad,
    ( SELECT jsonb_agg(jsonb_build_object('dia', to_char(d.d, 'DD/MM'::text), 'total', COALESCE(y.n, 0::bigint), 'escalados', COALESCE(y.e, 0::bigint)) ORDER BY d.d) AS jsonb_agg
           FROM generate_series(((now() AT TIME ZONE 'America/Bogota'::text)::date - 6)::timestamp with time zone, (now() AT TIME ZONE 'America/Bogota'::text)::date::timestamp with time zone, '1 day'::interval) d(d)
             LEFT JOIN ( SELECT (base.created_at AT TIME ZONE 'America/Bogota'::text)::date AS dd,
                    count(*) AS n,
                    count(*) FILTER (WHERE base.requiere_escalamiento) AS e
                   FROM base
                  GROUP BY ((base.created_at AT TIME ZONE 'America/Bogota'::text)::date)) y ON y.dd = d.d::date) AS tendencia_7d,
    ( SELECT jsonb_build_object('total', count(*), 'kb_resuelto', count(*) FILTER (WHERE gest.bucket = 'kb_resuelto'::text), 'kb_por_aprobar', count(*) FILTER (WHERE gest.bucket = 'kb_por_aprobar'::text), 'interno_ingenieria', count(*) FILTER (WHERE gest.bucket = 'interno_ingenieria'::text), 'interno_datos', count(*) FILTER (WHERE gest.bucket = 'interno_datos'::text), 'interno_manual', count(*) FILTER (WHERE gest.bucket = 'interno_manual'::text), 'pct_kb', round(100.0 * count(*) FILTER (WHERE gest.bucket ~~ 'kb_%'::text)::numeric / NULLIF(count(*), 0)::numeric, 0), 'casos', COALESCE(( SELECT jsonb_object_agg(z.b, z.cs) AS jsonb_object_agg
                   FROM ( SELECT gest_1.bucket AS b,
                            jsonb_agg(gest_1.numero_caso ORDER BY gest_1.numero_caso) AS cs
                           FROM gest gest_1
                          GROUP BY gest_1.bucket) z), '{}'::jsonb)) AS jsonb_build_object
           FROM gest) AS gestion_24h;

-- v_resumen_diario: Métricas de 24 h para P4. Cambios del 28 oct: cada patrón trae destino y regla_destino calculados por regla fija (P4 ya no elige el destino) e incidentes agrupados por firma, producto, país y código, con el número de oleadas.
create or replace view public.v_resumen_diario as
WITH base AS (
         SELECT t.id AS ticket_id,
            t.numero_caso,
            t.cliente,
            t.pais,
            t.asunto,
            t.created_at,
            c.severidad,
            c.origen_falla,
            c.producto,
            c.codigo_motivo,
            c.accion_sugerida,
            c.requiere_escalamiento,
            c.latencia_ms,
            c.tokens_entrada,
            c.tokens_salida,
            r.estado AS estado_respuesta
           FROM tickets t
             JOIN clasificaciones c ON c.ticket_id = t.id
             LEFT JOIN respuestas r ON r.ticket_id = t.id
          WHERE NOT t.es_set_prueba AND t.created_at > (now() - '24:00:00'::interval)
        ), sla AS (
         SELECT base.ticket_id,
            base.numero_caso,
            base.cliente,
            base.pais,
            base.asunto,
            base.created_at,
            base.severidad,
            base.origen_falla,
            base.producto,
            base.codigo_motivo,
            base.accion_sugerida,
            base.requiere_escalamiento,
            base.latencia_ms,
            base.tokens_entrada,
            base.tokens_salida,
            base.estado_respuesta,
                CASE base.severidad
                    WHEN 'P1'::text THEN '00:30:00'::interval
                    WHEN 'P2'::text THEN '02:00:00'::interval
                    WHEN 'P3'::text THEN '24:00:00'::interval
                    ELSE '48:00:00'::interval
                END AS limite
           FROM base
        )
 SELECT (now() AT TIME ZONE 'America/Bogota'::text) AS generado_en,
    ( SELECT count(*) AS count
           FROM base) AS tickets_24h,
    ( SELECT COALESCE(jsonb_object_agg(x.severidad, x.n), '{}'::jsonb) AS "coalesce"
           FROM ( SELECT base.severidad,
                    count(*) AS n
                   FROM base
                  GROUP BY base.severidad) x) AS por_severidad,
    ( SELECT COALESCE(jsonb_object_agg(x.origen_falla, x.n), '{}'::jsonb) AS "coalesce"
           FROM ( SELECT base.origen_falla,
                    count(*) AS n
                   FROM base
                  GROUP BY base.origen_falla) x) AS por_origen,
    ( SELECT count(*) AS count
           FROM base
          WHERE base.requiere_escalamiento) AS escalados_ingenieria,
    ( SELECT round(100.0 * avg((base.accion_sugerida = ANY (ARRAY['responder_con_kb'::text, 'comunicado_proactivo'::text]))::integer), 1) AS round
           FROM base) AS pct_resoluble_sin_escalar,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('caso', sla.numero_caso, 'cliente', sla.cliente, 'pais', sla.pais, 'severidad', sla.severidad, 'asunto', sla.asunto, 'desde', to_char((sla.created_at AT TIME ZONE 'America/Bogota'::text), 'DD/MM HH24:MI'::text), 'minutos_abierto', round(EXTRACT(epoch FROM now() - sla.created_at) / 60::numeric), 'limite_min', EXTRACT(epoch FROM sla.limite) / 60::numeric) ORDER BY sla.severidad, sla.created_at), '[]'::jsonb) AS "coalesce"
           FROM sla
          WHERE COALESCE(sla.estado_respuesta, 'pendiente'::text) = 'pendiente'::text AND (now() - sla.created_at) > (sla.limite * 0.8::double precision)) AS sla_en_riesgo,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('firma', x.firma, 'producto', x.producto, 'pais', x.pais, 'tickets', COALESCE(array_length(x.casos, 1), 0), 'codigo', x.codigo, 'casos', x.casos, 'desde', to_char((x.desde AT TIME ZONE 'America/Bogota'::text), 'DD/MM HH24:MI'::text), 'estado', x.estado, 'oleadas', x.oleadas) ORDER BY x.desde), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT i.firma,
                    i.producto,
                    i.pais,
                    i.codigo_motivo AS codigo,
                    min(COALESCE(i.inicio_at, i.created_at)) AS desde,
                    count(DISTINCT i.id) AS oleadas,
                        CASE
                            WHEN bool_or(i.estado = 'abierto'::text) THEN 'abierto'::text
                            ELSE 'cerrado'::text
                        END AS estado,
                    array_agg(DISTINCT c.caso ORDER BY c.caso) FILTER (WHERE c.caso IS NOT NULL) AS casos
                   FROM incidentes i
                     LEFT JOIN LATERAL unnest(i.casos) c(caso) ON true
                  WHERE i.created_at > (now() - '24:00:00'::interval)
                  GROUP BY i.firma, i.producto, i.pais, i.codigo_motivo) x) AS incidentes,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('patron', ((x.producto || ' · '::text) || x.origen_falla) || COALESCE(' · '::text || x.codigo_motivo, ''::text), 'tickets', x.n, 'casos', x.casos, 'destino',
                CASE
                    WHEN x.origen_falla = 'truora'::text THEN 'Ingeniería'::text
                    WHEN x.origen_falla = 'fuente_externa_gobierno'::text THEN 'Comunicación proactiva'::text
                    WHEN x.origen_falla = 'usuario_final'::text AND x.n >= 5 THEN 'Producto'::text
                    WHEN x.origen_falla = ANY (ARRAY['usuario_final'::text, 'integracion_cliente'::text, 'meta_whatsapp'::text, 'no_aplica'::text]) THEN 'KB/autoservicio'::text
                    ELSE 'Revisión N2'::text
                END, 'regla_destino',
                CASE
                    WHEN x.origen_falla = 'truora'::text THEN 'falla de plataforma'::text
                    WHEN x.origen_falla = 'fuente_externa_gobierno'::text THEN 'fuente externa: avisar a clientes y vigilar la fuente'::text
                    WHEN x.origen_falla = 'usuario_final'::text AND x.n >= 5 THEN '5 o más rechazos del usuario final en 24 h: fricción en el flujo'::text
                    WHEN x.origen_falla = ANY (ARRAY['usuario_final'::text, 'integracion_cliente'::text, 'meta_whatsapp'::text, 'no_aplica'::text]) THEN 'causa del cliente, del usuario o de Meta: se resuelve con KB'::text
                    ELSE 'origen indeterminado'::text
                END) ORDER BY x.n DESC), '[]'::jsonb) AS "coalesce"
           FROM ( SELECT base.producto,
                    base.origen_falla,
                    base.codigo_motivo,
                    count(*) AS n,
                    array_agg(base.numero_caso ORDER BY base.numero_caso) AS casos
                   FROM base
                  GROUP BY base.producto, base.origen_falla, base.codigo_motivo
                 HAVING count(*) >= 2) x) AS patrones,
    ( SELECT COALESCE(jsonb_object_agg(x.estado, x.n), '{}'::jsonb) AS "coalesce"
           FROM ( SELECT r.estado,
                    count(*) AS n
                   FROM respuestas r
                     JOIN base b ON b.ticket_id = r.ticket_id
                  GROUP BY r.estado) x) AS borradores,
    ( SELECT round(100.0 * count(*) FILTER (WHERE r.estado = 'aprobado'::text)::numeric / NULLIF(count(*) FILTER (WHERE r.estado = ANY (ARRAY['aprobado'::text, 'editado'::text, 'rechazado'::text])), 0)::numeric, 1) AS round
           FROM respuestas r
             JOIN base b ON b.ticket_id = r.ticket_id) AS pct_borradores_sin_edicion,
    ( SELECT round(avg(base.latencia_ms) / 1000.0, 1) AS round
           FROM base) AS seg_promedio_clasificacion,
    ( SELECT round((sum(base.tokens_entrada)::numeric * 0.15 + sum(base.tokens_salida)::numeric * 0.60) / 1000000::numeric / NULLIF(count(*), 0)::numeric, 5) AS round
           FROM base) AS costo_usd_por_ticket_p1;

-- v_caso_detalle: Una fila por caso para las consultas del bot (P5) y los correos. Cambio del 28 oct: el incidente del caso agrupa las oleadas del mismo problema.
create or replace view public.v_caso_detalle as
SELECT t.numero_caso,
    t.ticket_ref,
    t.created_at AS recibido_at,
    t.cliente,
    t.pais,
    t.canal,
    t.asunto,
    t.cuerpo,
    c.severidad,
    c.origen_falla,
    c.producto,
    c.ambiente,
    c.codigo_motivo,
    c.accion_sugerida,
    c.requiere_escalamiento,
    c.justificacion,
    c.datos_faltantes,
    c.confianza,
    c.created_at AS clasificado_at,
    r.tipo AS respuesta_tipo,
    r.estado AS respuesta_estado,
    r.borrador,
    r.texto_final,
    r.revisado_at,
    e.estado AS escalamiento_estado,
    e.hipotesis,
    e.ficha,
    e.created_at AS escalado_at,
    i.incidente,
    t.id AS ticket_id,
    r.id AS respuesta_id,
    e.id AS escalamiento_id,
    r.enviado_at AS correo_cliente_enviado_at,
    e.confirmado_at AS correo_ingenieria_enviado_at,
    ( SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', m.tipo, 'estado', m.estado, 'destinatario', m.destinatario, 'enviado_at', m.created_at) ORDER BY m.created_at), '[]'::jsonb) AS "coalesce"
           FROM correos_enviados m
          WHERE m.ticket_id = t.id) AS correos
   FROM tickets t
     LEFT JOIN LATERAL ( SELECT x.id,
            x.created_at,
            x.ticket_id,
            x.modelo,
            x.prompt_version,
            x.producto,
            x.pais,
            x.ambiente,
            x.tipo,
            x.origen_falla,
            x.codigo_motivo,
            x.severidad,
            x.confianza,
            x.justificacion,
            x.datos_faltantes,
            x.requiere_escalamiento,
            x.accion_sugerida,
            x.json_crudo,
            x.json_valido,
            x.error,
            x.latencia_ms,
            x.tokens_entrada,
            x.tokens_salida,
            x.costo_usd
           FROM clasificaciones x
          WHERE x.ticket_id = t.id
          ORDER BY x.created_at DESC
         LIMIT 1) c ON true
     LEFT JOIN LATERAL ( SELECT x.id,
            x.created_at,
            x.ticket_id,
            x.clasificacion_id,
            x.tipo,
            x.borrador,
            x.estado,
            x.texto_final,
            x.revisado_at,
            x.enviado_at
           FROM respuestas x
          WHERE x.ticket_id = t.id
          ORDER BY x.created_at DESC
         LIMIT 1) r ON true
     LEFT JOIN LATERAL ( SELECT x.id,
            x.created_at,
            x.ticket_id,
            x.clasificacion_id,
            x.ficha,
            x.hipotesis,
            x.estado,
            x.confirmado_at
           FROM escalamientos x
          WHERE x.ticket_id = t.id
          ORDER BY x.created_at DESC
         LIMIT 1) e ON true
     LEFT JOIN LATERAL ( SELECT jsonb_build_object('firma', b.firma, 'codigo_motivo', b.codigo_motivo, 'estado',
                CASE
                    WHEN bool_or(j.estado = 'abierto'::text) THEN 'abierto'::text
                    ELSE 'cerrado'::text
                END, 'detectado_at', min(j.created_at), 'inicio_at', min(COALESCE(j.inicio_at, j.created_at)), 'casos', array_agg(DISTINCT cs.caso ORDER BY cs.caso) FILTER (WHERE cs.caso IS NOT NULL), 'oleadas', count(DISTINCT j.id)) AS incidente
           FROM ( SELECT x.id,
                    x.created_at,
                    x.producto,
                    x.pais,
                    x.firma,
                    x.codigo_motivo,
                    x.ticket_ids,
                    x.mensaje_alerta,
                    x.estado,
                    x.casos,
                    x.inicio_at
                   FROM incidentes x
                  WHERE t.id = ANY (x.ticket_ids)
                  ORDER BY x.created_at DESC
                 LIMIT 1) b
             JOIN incidentes j ON j.firma = b.firma AND NOT j.producto IS DISTINCT FROM b.producto AND NOT j.pais IS DISTINCT FROM b.pais AND NOT j.codigo_motivo IS DISTINCT FROM b.codigo_motivo AND j.created_at >= (b.created_at - '24:00:00'::interval) AND j.created_at <= (b.created_at + '24:00:00'::interval)
             LEFT JOIN LATERAL unnest(j.casos) cs(caso) ON true
          GROUP BY b.firma, b.codigo_motivo) i ON true;

-- Prompt P4: v1 elegía el destino de cada patrón (y se equivocó); v2 lo copia de SQL;
-- v3 además redacta en lenguaje natural. Queda activa v3.
update public.prompts set activo = false where nombre = 'P4';
insert into public.prompts (nombre, version, activo, notas, texto) values (
  'P4', 'P4-v2', false,
  $p$v2: el destino de cada patrón lo calcula SQL (v_resumen_diario.patrones.destino). En v1 el modelo eligió el destino y envió un patrón de origen truora a Comunicación proactiva en vez de Ingeniería (28/10).$p$,
  $p$Eres el asistente del Líder de Soporte. Con las métricas de las últimas 24 horas (JSON calculado en SQL) escribe el resumen de la mañana para el líder.

Reglas:
- Usa SOLO las cifras y los textos del JSON. No calcules porcentajes nuevos ni inventes datos. Si un bloque está vacío, dilo en una línea.
- Español, directo, máximo 180 palabras. Sin saludo ni despedida.
- Estructura con estos títulos exactos:
  Estado: tickets, severidades y % resoluble sin escalar.
  SLA en riesgo: cada caso con cliente, severidad y minutos abiertos frente al límite. Primero los P1.
  Incidentes: firma (fuente externa o plataforma), país, producto y tickets.
  Patrones: cada patrón con su destino. Copia el destino EXACTAMENTE del campo "destino" del JSON y explícalo con el campo "regla_destino". Nunca elijas ni cambies el destino.
  Calidad de la IA: % de borradores aprobados sin edición, segundos promedio y costo por ticket.
  Prioridad de hoy: una sola acción, la de mayor impacto, justificada con una cifra del JSON.
Devuelve solo el texto.$p$)
on conflict (version) do update set activo = excluded.activo, notas = excluded.notas, texto = excluded.texto;
insert into public.prompts (nombre, version, activo, notas, texto) values (
  'P4', 'P4-v3', true,
  $p$v3: misma regla que v2 (destino calculado en SQL, el modelo no lo elige) pero redactado en lenguaje natural: sin nombres de campos ni valores técnicos con guion bajo. v2 copiaba etiquetas como "regla_destino:" y "firma: fuente_externa" (28/10).$p$,
  $p$Eres el asistente del Líder de Soporte. Con las métricas de las últimas 24 horas (JSON calculado en SQL) escribe el resumen de la mañana para el líder, como lo escribiría un analista senior: claro, directo y en español natural.

Reglas de contenido:
- Usa SOLO las cifras y los datos del JSON. No calcules porcentajes nuevos ni inventes datos. Si un bloque está vacío, dilo en una línea.
- El destino de cada patrón viene en el campo "destino" y su motivo en "regla_destino". Usa ese destino tal cual; nunca lo elijas ni lo cambies.

Reglas de redacción:
- Nunca escribas nombres de campos del JSON (destino, regla_destino, firma, minutos_abierto, limite_min, etc.) ni dos puntos después de ellos.
- Nunca escribas valores técnicos con guion bajo. Tradúcelos: fuente_externa_gobierno o fuente_externa → "fuente externa (gobierno)"; truora o plataforma → "plataforma de Truora"; integracion_cliente → "integración del cliente"; usuario_final → "usuario final"; meta_whatsapp → "Meta / WhatsApp"; identidad → "validación de identidad". Los códigos de motivo (por ejemplo government_database_unavailable) sí van tal cual, entre paréntesis.
- Escribe en frases cortas, sin saludo ni despedida. Máximo 170 palabras.

Estructura, con estos títulos exactos (cada título al inicio de su línea):
Estado: una frase con el total de tickets, cuántos son P1 y P2 (y P3/P4 si hay) y el % que se resuelve sin escalar.
SLA en riesgo: una línea por caso con este formato: "#1046 · P1 · Cliente (ficticio) · 1.044 min de 30". Primero los P1.
Incidentes: una frase por incidente. Ejemplo: "Fuente externa (gobierno) en validación de identidad, Colombia: 7 tickets afectados."
Patrones: una línea por patrón con este formato: "Validación de identidad · fuente externa (government_database_unavailable) → Comunicación proactiva: es una fuente externa, hay que avisar a los clientes y vigilar la fuente."
Calidad de la IA: una frase con el % de borradores aprobados sin edición, los segundos promedio de clasificación y el costo por ticket en USD.
Prioridad de hoy: una sola acción, la de mayor impacto, justificada con una cifra del JSON.
Devuelve solo el texto.$p$)
on conflict (version) do update set activo = excluded.activo, notas = excluded.notas, texto = excluded.texto;
