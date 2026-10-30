# Retos y cómo los superé

Responde al punto **d** de las notas de la prueba y a los criterios de *resolución de problemas y autonomía*: cómo gestioné los obstáculos, dónde busqué documentación, cuándo replanteé el enfoque y qué no sé hacer todavía. Son los 7 retos que cambiaron el resultado; los ajustes menores quedan en el historial del repositorio.

| # | Reto | Cómo lo superé | Documentación o replanteamiento |
| --- | --- | --- | --- |
| 1 | **Validar que el problema fuera real sin datos internos de Truora.** Casi no hay reseñas públicas (6 en Capterra). | Usé la documentación técnica pública como evidencia de los dolores y agregué al clasificador el campo `origen_falla`: separa lo que es de Truora de lo que es del gobierno, de Meta, de la integración del cliente o del usuario final. Un dato sobre reintentos de webhooks venía de una página que ya no existe (404): lo retiré en vez de afirmarlo. | dev.truora.com (motivos de rechazo, reglas de WhatsApp, Hooks, revisión manual, migración de `user_phone_number`), status.truora.com. **Replanteamiento:** de "clasificar tickets" a "decidir primero a quién le toca". |
| 2 | **La API key de OpenAI que entregó Truora no funcionaba.** | La probé con una llamada real antes de concluir (`401 invalid_api_key`), lo reporté y seguí con una clave propia del mismo proveedor. Esa clave no tenía saldo (`429 insufficient_quota`): cargué un monto mínimo con límite de gasto. | Códigos de error de la API de OpenAI. |
| 3 | **La primera versión del clasificador acertaba poco:** 73 % en severidad, 67 % en origen y 4 escalamientos innecesarios a Ingeniería. | Revisé los 30 errores uno a uno y los agrupé en 4 patrones (cambios del cliente atribuidos a la plataforma, severidad inflada, origen adivinado en vez de "indeterminado", consultas tratadas como "no aplica"). Con P1-v3 llegó a **80 % y 87 %, 1 escalamiento innecesario y 0 P1 perdidos**. Paré en la segunda corrida para no sobreajustar al mismo set. | Medición en SQL (`v_metricas_corrida`), no autoevaluada por el modelo. Detalle en `docs/evaluacion.md`. |
| 4 | **Alertas de incidente falsas y duplicadas.** Las corridas de evaluación disparaban incidentes, y la segunda oleada de una misma caída creaba un incidente nuevo. | Separé los datos de prueba de la operación con una vista que excluye el set de evaluación. El ticket que llega con un incidente abierto (24 h) se suma a ese incidente sin repetir la alerta. | Revisión de las ejecuciones de n8n y de la tabla `incidentes`. |
| 5 | **El modelo tomaba decisiones que no debía.** En el resumen diario mandó una falla de plataforma a "Comunicación proactiva" y, al corregirlo, empezó a copiar etiquetas técnicas. | En lugar de alargar el prompt, le quité la decisión: SQL calcula las cifras, el semáforo y el destino de cada patrón con una regla fija; la IA solo redacta. | **Replanteamiento:** la regla de diseño pasó a ser "SQL decide, la IA redacta". P4 tuvo 3 versiones hasta llegar ahí. |
| 6 | **El control humano fallaba al usar el bot de verdad.** "Editar" envió al cliente una pregunta como si fuera la respuesta, y un doble toque en "Confirmar escalamiento" mandó dos correos a Ingeniería. | Antes de enviar, el líder ve el texto final y lo confirma con "Enviar al cliente". Cada acción reserva el registro en la base de datos (`abierto → enviando`); el segundo toque no encuentra nada que enviar y avisa "ya se envió". Verificado con un triple toque: 1 solo correo. | Pruebas en Telegram como las haría el líder, no solo desde el editor de n8n. |
| 7 | **El reporte del líder era largo y no llevaba al detalle.** En Telegram una foto no admite clics por zona y un álbum no admite botones. | Lo rediseñé en capas: una foto con el tablero (severidad × SLA), los pendientes que necesitan decisión y botones de detalle. Agregué un tablero web (flujo F) donde cada cifra abre la lista de casos y cada caso abre su ficha, con enlace de vuelta al bot para aprobar. | Límites de Telegram (álbum sin botones) y de QuickChart (las URLs cortas gratuitas vencen a los 3 días: uso URLs completas). **Replanteamiento:** lo ejecutivo primero, el detalle a un toque. |

## Lo que todavía no sé hacer

- **No soy desarrollador.** Construí los flujos, las vistas y el repositorio con apoyo de Claude Code; cada nodo lo puedo explicar, pero no escribiría este código solo desde cero.
- **No lo he operado con tickets reales.** Falta conectarlo a un help desk, validarlo con un set separado de tickets anonimizados y medir la deriva del modelo en producción.
- **Costo completo de la IA.** Hoy solo se mide el costo de P1; falta registrar el de P2 a P5.
- **Seguridad del tablero web.** Usa una llave en el enlace; en producción necesita autenticación real.

## Versiones

| Pieza | Versiones |
| --- | --- |
| Prompts | 8 versiones en la tabla `prompts`: P1 (v2 → v3), P4 (v1 → v3), P2, P3 y P5 (v1). 5 activas |
| Evaluación del clasificador | 2 corridas sobre 30 tickets etiquetados |
| Flujos de n8n | 5: A triage, C Telegram, D reporte del líder, E evaluación, F tablero web |
| Base de datos | 22 migraciones en Supabase, consolidadas en 13 archivos de `sql/` |
