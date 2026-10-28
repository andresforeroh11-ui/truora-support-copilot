# Bitácora de retos

| Reto | Qué intenté | Qué funcionó | Fuente |
| --- | --- | --- | --- |
| Validar que el enfoque respondiera a dolores reales de Truora | Buscar reseñas públicas: casi no hay | Usar documentación técnica, página de estado y vacantes; agregar `origen_falla` al clasificador | dev.truora.com, status.truora.com, Capterra |
| Dato de "5 reintentos con backoff" del webhook | Verificarlo en la guía original | La página ya no existe (404) y la guía vigente no lo menciona: se retiró de la KB en vez de afirmarlo | dev.truora.com/guides/web_webhooks/ |
| Conector de Supabase no veía el proyecto | Autorizar el conector | El proyecto estaba en otra cuenta: reconectar con la cuenta dueña del proyecto | Supabase MCP (error "sin permiso") |
| API key de OpenAI entregada por Truora | Repegarla, revisar formato | Llamada real en n8n: `401 invalid_api_key` con la clave completa → no está activa; se reportó a Truora y se siguió con clave propia | Error de la API de OpenAI |
| Clave propia sin saldo | Ejecutar el flujo | `429 insufficient_quota` → cargar saldo mínimo con límite de gasto | Error de la API de OpenAI |
| Precisión de la corrida 1 (73% severidad, 67% origen, 4 escalamientos innecesarios) | Revisar los errores uno a uno | Agruparlos en 4 patrones y crear P1-v3 versionado en Supabase; corrida 2: 80% / 87% / 1 | docs/evaluacion.md |
| Alertas de incidente falsas (México "plataforma" con 13 tickets; Colombia duplicada) | Revisar qué filas leía la detección | Las 60 clasificaciones de las corridas de evaluación contaban como tickets recientes: se creó la vista `v_clasificaciones_vivas` (excluye el set de prueba). Prueba nueva: 1 sola alerta, firma fuente externa, 4 tickets de Colombia | Supabase, ejecución n8n #19–20 |
| El nodo de Telegram no permite botones condicionales | Un solo mensaje con todos los botones | Un IF después de componer el mensaje: con ficha P3 se envía la versión con el botón "Confirmar escalamiento"; sin ficha, la de 3 botones | Workflow A |
| Las consultas al bot fallaban antes de llegar al switch | Leer la respuesta antes de decidir la acción | "Leer respuesta" necesitaba un ID que las consultas no traen: se movió a la rama de Aprobar | Workflow C |
| Enviar correos sin credencial publicada | Publicar los cambios de C antes de conectar Gmail | Se editó el borrador sin publicar (la versión activa siguió atendiendo botones) y se publicó solo cuando la credencial de Gmail existió; cada envío registra estado y error | n8n, tabla correos_enviados |
| Leer la vacante completa para alinear el agente y la HV | Extraer el texto de la página de forma automática | La página bloquea la extracción automática: se pegó el texto y se guardó en el proyecto | Truora careers (PeopleForce) |

## 28 oct · Resumen diario, gráficas y uso real del bot

| Reto | Qué intenté | Qué funcionó | Fuente |
| --- | --- | --- | --- |
| Gráficas en Telegram y en el correo del resumen | URLs cortas de QuickChart | Las URLs cortas gratuitas vencen a los 3 días (un correo abierto después mostraría imágenes rotas): se usan URLs completas, que llevan la configuración dentro y no vencen | Documentación de QuickChart |
| Medir cuántos casos se resuelven con base de conocimiento y cuántos van a gestión interna | Hablar de casos "automáticos" | 5 categorías calculadas en SQL con el estado real del caso; se dice "resuelto con base de conocimiento" porque siempre hay aprobación humana | `v_graficas_diarias.gestion_24h` (80 % con KB el 28 oct) |
| P4 envió a "Comunicación proactiva" un patrón de origen `truora` | P4-v1 elegía el destino con definiciones en el prompt | El destino se calcula en SQL con una regla fija; P4-v2 solo lo copia y la línea fija del reporte lo muestra desde SQL | Ejecución del resumen 28 oct 11:12 |
| P4-v2 copiaba etiquetas técnicas ("regla_destino:", "firma: fuente_externa") | Pedirle copiar el destino tal cual | P4-v3 prohíbe nombres de campos y valores con guion bajo y fija el formato de cada línea con ejemplos | Ejecución del 28 oct 12:03 |
| El mismo incidente (Registraduría) salía en dos renglones | Causa: la búsqueda de incidentes abiertos solo miraba 30 min; la segunda oleada (1 h después) creó otro | Buscar abiertos de 24 h y sumar el ticket al incidente existente sin repetir la alerta; las vistas agrupan las oleadas | Tabla `incidentes` (19:17 y 20:37 del 27 oct) |
| Gráficas poco profesionales y sin valores | Paleta genérica | Paleta del CSS público de truora.com (sin logo), números en cada barra, número y % en la dona; revisión visual antes de publicar | truora.com |
| La línea de tendencia bajaba de 0 entre puntos | Suavizado con tensión 0.3 | Interpolación monótona | Revisión visual |
| El bot no respondía a "caso 1048 …" | La lógica estaba bien: el flujo C no recibía mensajes. Causa probable: probar el disparador de Telegram desde el editor deja el bot sin el webhook de producción | Re-publicar el flujo C. Regla: probarlo escribiéndole al bot, no desde el editor | Historial de ejecuciones del flujo C |
| La consulta decía que el incidente tenía 3 casos (faltaban 3) | `v_caso_detalle` tomaba solo el último registro de incidente | La vista agrupa las oleadas igual que el resumen | Consulta del caso 1048 |
| Al consultar un caso pendiente no salían los botones | La respuesta se enviaba sin teclado | Botones según el estado del caso (borrador pendiente, escalamiento abierto, ambos o ninguno) | Prueba en Telegram |
| "Editar" envió al cliente una pregunta ("cual es el borrador") como respuesta final | El mensaje de edición no mostraba el borrador y el texto respondido se enviaba sin revisión | La consulta muestra el borrador tal cual; Editar muestra el texto actual; el texto corregido solo se envía tras tocar "Enviar al cliente" viendo la versión final | Correo demo del caso #1048 |
