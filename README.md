# Truora Support Copilot

Copiloto de IA para el **Líder de Soporte** de una plataforma B2B de identidad, background checks, firma electrónica y WhatsApp con clientes en 5 países. Prueba técnica PT1 – AI First (Líder de Soporte Operations, Hispam).

> Solo datos sintéticos: clientes ficticios, sin datos reales de usuarios finales.

## El problema que resuelve
Una parte del volumen de soporte no es falla de la plataforma: son rechazos explicables, fuentes del gobierno caídas, decisiones de Meta o la integración del cliente. El copiloto separa eso en segundos para que **Ingeniería solo reciba lo que es suyo**, el cliente reciba una respuesta correcta en minutos y el líder vea los incidentes **antes que el cliente**.

## Cómo funciona

```
Formulario ─► Supabase (ticket con número de caso) ─► P1 clasifica (origen → severidad → ruta, JSON validado)
                              │
                              ├─► P2 redacta borrador / comunicado solo con la KB
                              ├─► P3 ficha para Ingeniería (solo si el origen es la plataforma)
                              ├─► Telegram: caso #, hora, clasificación, borrador y botones
                              │     ✅ Aprobar y enviar  → correo al cliente + confirmación en Telegram
                              │     ✏️ Editar            → muestra el borrador; el texto corregido
                              │                            se revisa y solo sale con «Enviar al cliente»
                              │     ❌ Rechazar
                              │     🛠 Confirmar escalamiento → correo a Ingeniería (solo si hay ficha)
                              └─► Detección de incidentes: 3+ tickets iguales en 30 min
                                  → alerta con firma, números de caso y desde cuándo ocurre
                                  → si ya hay uno abierto (24 h), el ticket se suma sin repetir la alerta
Consultas: "caso 1055 ¿ya se envió el correo?" → P5 responde solo con los datos de ese caso;
           si hay borrador pendiente lo muestra tal cual, con los botones que aplican.
Cada mañana (o con «🔄 Actualizar reporte»): semáforo, tablero severidad × SLA y decisiones pendientes
           calculados en SQL; P4 solo redacta la prioridad y la lectura del día
           → Telegram (foto del tablero + botones de detalle) y correo.
Tablero web (F): cada cifra abre sus casos y cada caso su ficha, con enlace al bot para aprobar o escalar.
```

Nada llega al cliente sin aprobación humana, y lo que se aprueba siempre se ve antes de enviarlo. Cada correo queda registrado en `correos_enviados`.

### Reporte del líder

| Bloque | De dónde sale |
| --- | --- |
| Semáforo, KPIs, decisiones pendientes, SLA en riesgo, incidentes y resueltos | `v_reporte_lider` (SQL) |
| Tablero severidad × estado de SLA, SLA de 1ª respuesta, pendientes por responsable | `v_tablero_b`, `v_tablero_casos` (SQL); foto en Telegram y página web (F) |
| Destino de cada patrón (Ingeniería, comunicación proactiva, Producto, KB) | Regla fija en SQL; P4 solo lo copia |
| Prioridad y lectura del día | Redactadas por P4 con las cifras ya calculadas |
| Gráficas: gestión de casos, origen × severidad, SLA por severidad, tendencia | `v_graficas_diarias` → QuickChart (solo conteos), en el correo y en "Más gráficas" |

Botones de detalle en Telegram: pendientes, SLA, incidentes, patrones, resueltos, gráficas, actualizar reporte y abrir tablero web. La ventana del reporte se configura en `config_reporte.ventana_horas` (24 = operación diaria; null = acumulado).

## Componentes

| Pieza | Herramienta | Archivo |
| --- | --- | --- |
| A · Copiloto de triage y escalamiento | n8n (28 nodos) | `workflows/A_copiloto_triage.json` |
| C · Aprobación, correos, consultas y detalle del reporte | n8n + Telegram + Gmail (67 nodos) | `workflows/C_aprobacion_telegram.json` |
| D · Reporte del líder | n8n + Telegram + Gmail + QuickChart (lunes a viernes 7:24 y bajo demanda) | `workflows/D_resumen_diario.json` |
| E · Evaluación del clasificador | n8n, 30 tickets etiquetados | `workflows/E_evaluacion_clasificador.json` |
| F · Tablero web del líder | n8n (webhook que responde HTML) | `workflows/F_tablero_web.json` |
| Base de datos | Supabase (Postgres) | `sql/` |
| Prompts P1–P5 (versionados también en la tabla `prompts`) | OpenAI gpt-4o-mini | `prompts/` |
| Base de conocimiento: 145 motivos de rechazo + 6 artículos | Documentación pública de Truora | `data/`, tablas `kb_motivos`, `kb_articulos` |
| Set de prueba: 40 tickets (30 etiquetados a mano) | — | `data/tickets_sinteticos.csv` |

| Prompt | Qué hace |
| --- | --- |
| P1 | Clasifica origen, severidad y acción (JSON validado contra el esquema) |
| P2 | Redacta la respuesta o el comunicado solo con la KB |
| P3 | Arma la ficha de escalamiento con una hipótesis verificable |
| P4 | Redacta la prioridad y la lectura del día con cifras y destinos ya calculados en SQL (versión activa: v3) |
| P5 | Responde preguntas del líder sobre un caso, solo con la fila de `v_caso_detalle` |

## Base de datos (Supabase)

| Tabla / vista | Para qué |
| --- | --- |
| `tickets` | Entrada, con `numero_caso` legible (#1001…) y etiquetas de evaluación |
| `clasificaciones` | Salida de P1 con JSON crudo, tokens y latencia |
| `respuestas` | Borradores de P2, estado (pendiente, aprobado, editado, rechazado) y `enviado_at` |
| `escalamientos` | Fichas de P3 y estado (abierto → enviando → en_revision → cerrado; `enviando` evita correos duplicados) |
| `incidentes` | Alertas con firma, `casos` y `inicio_at` (desde cuándo ocurre) |
| `correos_enviados` | Cada correo: tipo, caso, destinatario, hora, estado e id de Gmail |
| `destinatarios_correo` | A quién va cada correo (cliente, Ingeniería, líder); se cambia sin tocar n8n |
| `prompts` | Prompts versionados; los workflows leen la versión activa |
| `kb_motivos`, `kb_articulos` | Base de conocimiento |
| `evaluaciones` + `v_metricas_corrida` | Precisión por corrida, calculada en SQL |
| `v_clasificaciones_vivas` | Solo tickets reales (excluye el set de evaluación) |
| `v_caso_detalle` | Una fila por caso: ticket, clasificación, borrador, ficha, incidente (agrupado por oleadas) y correos |
| `v_resumen_diario`, `resumenes_diarios` | Métricas de 24 h (con casos, hora "desde", destino de cada patrón e incidentes agrupados) y resúmenes de P4 |
| `v_graficas_diarias` | Conteos para las gráficas y la gestión de casos (KB vs interna) |
| `v_reporte_lider` | Semáforo, KPIs, decisiones, SLA en riesgo, incidentes y resueltos del reporte |
| `v_tablero_casos`, `v_tablero_b` | Tablero severidad × SLA: estado y responsable de cada caso, matriz, totales y SLA de 1ª respuesta |
| `config_reporte` | Ventana del reporte (`ventana_horas`) |

**Límites de SLA:** P1 30 min · P2 2 h · P3 24 h · P4 48 h. "En riesgo" = más del 80 % del límite sin respuesta aprobada.

**Destino de cada patrón (regla fija en SQL):** `truora` → Ingeniería · `fuente_externa_gobierno` → Comunicación proactiva · `usuario_final` con 5 o más casos en 24 h → Producto · `usuario_final`, `integracion_cliente`, `meta_whatsapp`, `no_aplica` → KB/autoservicio · resto → Revisión N2.

## Resultados de la evaluación

| Métrica | P1-v2 | P1-v3 |
| --- | --- | --- |
| Precisión de severidad | 73,3% | **80,0%** |
| Precisión de origen | 66,7% | **86,7%** |
| P1 no detectados | 0 | **0** |
| Escalamientos innecesarios | 4 | **1** |

Detalle y errores restantes: `docs/evaluacion.md`.

## Documentos de la entrega

| Documento | Para qué |
| --- | --- |
| Video (≤ 5 min) | Configuración del agente, paso de IA y resultado funcionando: _[enlace]_ |
| `docs/notas_entrega.md` | Notas que pide la prueba: proceso de pensamiento, prompts, uso de IA y retos |
| `docs/bitacora_retos.md` | Los 7 retos principales, documentación consultada, lo que no sé hacer y versiones |
| `docs/evaluacion.md` | Precisión del clasificador en 2 corridas y errores restantes |
| `docs/casos_demo.md` | Los 4 tickets de la demo del video y el resultado esperado |

## Cómo levantarlo desde cero
1. **Supabase:** crear un proyecto y correr los archivos de `sql/` en orden (01 → 13). Importar `data/kb_motivos.csv` a `kb_motivos`. En `10_correos.sql`, reemplazar `TU_CORREO_DE_PRUEBA` por el buzón donde quieres recibir los correos.
2. **n8n:** crear 4 credenciales: OpenAI (API key), Supabase (host + `service_role`), Telegram (token de @BotFather) y Gmail OAuth2 (*Sign in with Google*).
3. Importar los 5 JSON de `workflows/`, asignar las credenciales en cada nodo y reemplazar los marcadores: `TU_CHAT_ID` (tu ID de Telegram), `TU_BOT` (usuario del bot), `TU_INSTANCIA` (subdominio de n8n Cloud) y `TU_LLAVE_TABLERO` (una cadena aleatoria para el enlace del tablero web).
4. Publicar **C** (botones, correos y consultas), **D** (reporte programado) y **F** (tablero web).
5. Probar: abrir el formulario de **A** y enviar un ticket. Debe llegar el mensaje a Telegram; al tocar *Aprobar y enviar* llega el correo y la confirmación.
6. Consultar: escribir al bot `caso <número> ¿...?`.
7. Evaluar: en **E**, ajustar `corrida` y `prompt_version` en el nodo *Configuración* y ejecutar.

**Cambiar un prompt:** insertar una fila nueva en `prompts` con otra versión, marcarla `activo = true` y desactivar la anterior. No hay que tocar n8n.

**Ojo con el flujo C:** no lo pruebes desde el editor de n8n («Execute workflow» o «Listen for test event»). Eso apunta el bot a una URL de prueba y, al terminar, el bot deja de recibir mensajes en producción. Pruébalo escribiéndole al bot; si ya pasó, despublica y vuelve a publicar C.

## Seguridad y datos
- Las credenciales viven solo en n8n; los JSON exportados no las incluyen.
- RLS activo en todas las tablas sin políticas públicas: la clave anónima no lee nada.
- El bot de Telegram solo atiende al usuario configurado (`TU_CHAT_ID`).
- El tablero web exige la llave del enlace (sin ella responde 403) y no se indexa; en producción necesita autenticación real.
- Modo demo: como los clientes son ficticios, el correo "al cliente" llega a un buzón de prueba y aclara a quién iría en producción.
- Los prompts prohíben copiar datos personales de usuarios finales y mencionar "fraude" al cliente; P5 solo responde con datos del caso pedido.
- Las gráficas se generan en QuickChart (servicio externo) solo con conteos agregados: no viaja texto de tickets, clientes ni IDs.

## Siguientes pasos para producción
Conectar el help desk real (entrada de tickets y correo del contacto de cada cliente) en lugar del formulario; validar con un set separado de tickets reales anonimizados; consultar status.truora.com para confirmar fuentes caídas; registrar el costo de P2–P5 (hoy solo se mide P1); autenticación real en el tablero web.
