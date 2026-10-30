# Notas de entrega · Copiloto de Triage y Escalamiento

**Andrés Forero · Líder de Soporte Operations (Hispam) · Prueba PT1 – AI First**
Repositorio: `andresforeroh11-ui/truora-support-copilot` · Video: _[enlace]_

## 1. Proceso de pensamiento

**El rol.** El Líder de Soporte de Truora tiene que sostener los SLA de clientes B2B que integran por API en 5 países, escalar a Ingeniería con la información mínima, convertir tickets repetidos en mejoras y hacerlo con automatización e IA, sin crecer la plantilla al mismo ritmo.

**El problema que elegí.** La mayor parte del juicio diario del líder se va en decidir qué atender primero y qué escalar. En Truora eso tiene una particularidad: una parte del volumen no es falla propia. Son rechazos explicables (`blurry_image`, `process_started_late`), fuentes del gobierno caídas (`government_database_unavailable`), decisiones de Meta sobre líneas de WhatsApp o errores de la integración del cliente. Escalar eso a Ingeniería es ruido, y enterarse de una fuente caída cuando el cliente ya abrió ticket es tarde.

**Cómo lo validé.** Casi no hay reseñas públicas de Truora (6 en Capterra), así que usé su documentación técnica (catálogo de motivos de rechazo, reglas de WhatsApp, migración de `user_phone_number`, Hooks, revisión manual), su página de estado y sus vacantes. Los dolores del agente son hipótesis basadas en información pública, no datos internos.

**La solución.** Un copiloto que, por cada ticket, decide **de dónde viene la falla** antes de decidir qué hacer: clasifica origen y severidad, redacta la primera respuesta con la base de conocimiento, arma la ficha para Ingeniería solo si el origen es la plataforma, detecta incidentes (3+ tickets iguales en 30 min) diciendo si parecen fuente externa o plataforma, responde preguntas del líder sobre un caso y le entrega cada mañana un reporte con el tablero de severidad × SLA y lo que necesita su decisión. **Nada llega al cliente sin aprobación humana**, porque es un negocio de identidad y datos personales.

**Descartado:** respuesta automática sin humano (riesgo); tablero en Lovable (tiempo: el bot de Telegram y un tablero web servido por n8n cubren la interfaz); agrupar feedback para Producto como agente principal (menos medible en 4 días que la precisión de un clasificador).

**Stack:** formulario de n8n (entrada) → 5 workflows de n8n (A triage, C aprobación y consultas en Telegram, D reporte del líder, E evaluación, F tablero web) → OpenAI gpt-4o-mini → Supabase (tickets, salidas, prompts versionados, métricas) → bot de Telegram, correo y tablero web.

## 2. Prompts y por qué

| Prompt | Hace | Decisión de diseño |
| --- | --- | --- |
| **P1 Clasificador** | Origen → severidad → ruta, en JSON | Temperatura 0, salida validada por esquema; la decisión en 3 pasos separa *a quién le toca* de *cuánto duele*; "un origen externo no baja la severidad"; ejemplos few-shot con códigos reales de la documentación |
| **P2 Redactor** | Respuesta o comunicado proactivo | Solo usa la KB y el motivo de rechazo; pide datos en vez de inventar; nunca dice "fraude" ni pide datos personales completos, solo IDs de proceso |
| **P3 Ficha de escalamiento** | Ficha para Ingeniería | Solo corre si el origen es la plataforma (o indeterminado P1/P2); hipótesis verificable con su certeza y 3–5 cosas concretas que revisar |
| **P4 Resumen del líder** | Lectura del día y prioridad en el reporte | Las cifras, el semáforo y el destino de cada patrón los calcula SQL; la IA solo redacta |
| **P5 Consulta de caso** | Responde "caso 1052 ¿ya se envió?" desde Telegram | Responde solo con la fila del caso; si no está el dato, lo dice |

Todos los prompts viven versionados en la tabla `prompts`: cambiar uno no requiere tocar n8n.

**Medición.** 30 tickets sintéticos etiquetados a mano antes de correr el agente; las métricas las calcula SQL, no el modelo.

| Métrica | P1-v2 | P1-v3 |
| --- | --- | --- |
| Precisión de severidad | 73,3 % | **80,0 %** |
| Precisión de origen | 66,7 % | **86,7 %** |
| P1 no detectados | 0 | **0** |
| Escalamientos innecesarios a Ingeniería | 4 | **1** |

De v2 a v3 corregí 4 patrones de error: atribuir a la plataforma cambios del cliente, inflar severidad, adivinar el origen en vez de decir "indeterminado" y tratar consultas como "no aplica". Paré en la corrida 2 para no sobreajustar al mismo set; en producción mediría con un set separado.

## 3. Cómo usé IA para construir

- **Claude Code:** construir y depurar los workflows de n8n, las tablas y vistas de Supabase y el repositorio. Lo digo tal cual: no soy desarrollador, y cada nodo lo puedo explicar con mis palabras.
- **Claude:** investigar la documentación pública de Truora, armar la base de conocimiento (145 motivos de rechazo), redactar y ajustar los prompts y generar los 40 tickets sintéticos, que revisé y etiqueté uno a uno.
- **OpenAI gpt-4o-mini:** es el modelo **dentro** del agente. La API key que entregó Truora devolvió `401 invalid_api_key` en una llamada real; lo reporté y seguí con una clave propia del mismo proveedor.

## 4. Retos y cómo los superé

Los 7 retos principales, con la documentación que consulté y dónde replanteé el enfoque, están en `docs/bitacora_retos.md`. Los que más enseñan:

1. **Verificar antes de afirmar.** Validé el problema con la documentación pública de Truora; un dato de una página que ya no existe lo retiré. La API key entregada la probé con una llamada real (`401`) antes de concluir que no servía.
2. **Medir y parar a tiempo.** Agrupé los errores de la corrida 1 en 4 patrones y P1-v3 bajó los escalamientos innecesarios de 4 a 1 sin perder ningún P1. No hice una tercera corrida para no sobreajustar.
3. **Quitarle decisiones a la IA.** Cuando P4 eligió mal un destino, no alargué el prompt: SQL decide y la IA redacta.
4. **Probar como lo usa el líder.** Al usar el bot de verdad aparecieron dos fallas del control humano (editar y doble toque). Ahora el texto final siempre se ve antes de salir y cada envío ocurre una sola vez.

**Lo que todavía no sé hacer:** no soy desarrollador (construí con Claude Code y puedo explicar cada pieza), y no lo he operado sobre un help desk real. El siguiente paso es conectarlo al help desk, validarlo con tickets reales anonimizados, consultar status.truora.com para confirmar fuentes caídas y medir el costo de P2–P5.
