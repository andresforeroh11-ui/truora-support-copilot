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
                              │     ✏️ Editar            → texto corregido + correo al cliente
                              │     ❌ Rechazar
                              │     🛠 Confirmar escalamiento → correo a Ingeniería (solo si hay ficha)
                              └─► Detección de incidentes: 3+ tickets iguales en 30 min
                                  → alerta con firma, números de caso y desde cuándo ocurre
Consultas: "caso 1055 ¿ya se envió el correo?" → P5 responde solo con los datos de ese caso.
Cada mañana: P4 interpreta las métricas de 24 h calculadas en SQL → Telegram y correo.
```

Nada llega al cliente sin aprobación humana. Cada correo queda registrado en `correos_enviados`.

## Componentes

| Pieza | Herramienta | Archivo |
| --- | --- | --- |
| A · Copiloto de triage y escalamiento | n8n (26 nodos) | `workflows/A_copiloto_triage.json` |
| C · Aprobación, correos y consultas | n8n + Telegram + Gmail (42 nodos) | `workflows/C_aprobacion_telegram.json` |
| D · Resumen diario del líder | n8n + Telegram + Gmail (lunes a viernes 7:24) | `workflows/D_resumen_diario.json` |
| E · Evaluación del clasificador | n8n, 30 tickets etiquetados | `workflows/E_evaluacion_clasificador.json` |
| Base de datos | Supabase (Postgres) | `sql/` |
| Prompts P1–P5 (versionados también en la tabla `prompts`) | OpenAI gpt-4o-mini | `prompts/` |
| Base de conocimiento: 145 motivos de rechazo + 6 artículos | Documentación pública de Truora | `data/`, tablas `kb_motivos`, `kb_articulos` |
| Set de prueba: 40 tickets (30 etiquetados a mano) | — | `data/tickets_sinteticos.csv` |

| Prompt | Qué hace |
| --- | --- |
| P1 | Clasifica origen, severidad y acción (JSON validado contra el esquema) |
| P2 | Redacta la respuesta o el comunicado solo con la KB |
| P3 | Arma la ficha de escalamiento con una hipótesis verificable |
| P4 | Redacta el resumen diario con cifras ya calculadas en SQL |
| P5 | Responde preguntas del líder sobre un caso, solo con la fila de `v_caso_detalle` |

## Base de datos (Supabase)

| Tabla / vista | Para qué |
| --- | --- |
| `tickets` | Entrada, con `numero_caso` legible (#1001…) y etiquetas de evaluación |
| `clasificaciones` | Salida de P1 con JSON crudo, tokens y latencia |
| `respuestas` | Borradores de P2, estado (pendiente, aprobado, editado, rechazado) y `enviado_at` |
| `escalamientos` | Fichas de P3, estado y `confirmado_at` (correo a Ingeniería) |
| `incidentes` | Alertas con firma, `casos` y `inicio_at` (desde cuándo ocurre) |
| `correos_enviados` | Cada correo: tipo, caso, destinatario, hora, estado e id de Gmail |
| `destinatarios_correo` | A quién va cada correo (cliente, Ingeniería, líder); se cambia sin tocar n8n |
| `prompts` | Prompts versionados; los workflows leen la versión activa |
| `kb_motivos`, `kb_articulos` | Base de conocimiento |
| `evaluaciones` + `v_metricas_corrida` | Precisión por corrida, calculada en SQL |
| `v_clasificaciones_vivas` | Solo tickets reales (excluye el set de evaluación) |
| `v_caso_detalle` | Una fila por caso: ticket, clasificación, borrador, ficha, incidente y correos |
| `v_resumen_diario`, `resumenes_diarios` | Métricas de 24 h (con casos y hora "desde") y resúmenes de P4 |

## Resultados de la evaluación

| Métrica | P1-v2 | P1-v3 |
| --- | --- | --- |
| Precisión de severidad | 73,3% | **80,0%** |
| Precisión de origen | 66,7% | **86,7%** |
| P1 no detectados | 0 | **0** |
| Escalamientos innecesarios | 4 | **1** |

Detalle y errores restantes: `docs/evaluacion.md`. Retos y cómo se resolvieron: `docs/bitacora_retos.md`.

## Cómo levantarlo desde cero
1. **Supabase:** crear un proyecto y correr los archivos de `sql/` en orden (01 → 10). Importar `data/kb_motivos.csv` a `kb_motivos`. En `10_correos.sql`, reemplazar `TU_CORREO_DE_PRUEBA` por el buzón donde quieres recibir los correos.
2. **n8n:** crear 4 credenciales: OpenAI (API key), Supabase (host + `service_role`), Telegram (token de @BotFather) y Gmail OAuth2 (*Sign in with Google*).
3. Importar los 4 JSON de `workflows/`, asignar las credenciales en cada nodo y reemplazar `TU_CHAT_ID` / `TU_USER_ID` por tu ID de Telegram.
4. Publicar **C** (botones, correos y consultas) y **D** (resumen programado).
5. Probar: abrir el formulario de **A** y enviar un ticket. Debe llegar el mensaje a Telegram; al tocar *Aprobar y enviar* llega el correo y la confirmación.
6. Consultar: escribir al bot `caso <número> ¿...?`.
7. Evaluar: en **E**, ajustar `corrida` y `prompt_version` en el nodo *Configuración* y ejecutar.

**Cambiar un prompt:** insertar una fila nueva en `prompts` con otra versión, marcarla `activo = true` y desactivar la anterior. No hay que tocar n8n.

## Seguridad y datos
- Las credenciales viven solo en n8n; los JSON exportados no las incluyen.
- RLS activo en todas las tablas sin políticas públicas: la clave anónima no lee nada.
- El bot de Telegram solo atiende al usuario configurado (`TU_USER_ID`).
- Modo demo: como los clientes son ficticios, el correo "al cliente" llega a un buzón de prueba y aclara a quién iría en producción.
- Los prompts prohíben copiar datos personales de usuarios finales y mencionar "fraude" al cliente; P5 solo responde con datos del caso pedido.

## Siguientes pasos para producción
Conectar el help desk real (entrada de tickets y correo del contacto de cada cliente) en lugar del formulario; validar con un set separado de tickets reales anonimizados; consultar status.truora.com para confirmar fuentes caídas; registrar el costo de P2–P5 (hoy solo se mide P1); tablero para el equipo.
