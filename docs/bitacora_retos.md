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
