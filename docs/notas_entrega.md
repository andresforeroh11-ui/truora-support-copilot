# Notas de entrega · Copiloto de Triage y Escalamiento

**Andrés Forero · Líder de Soporte Operations (Hispam) · Prueba PT1 – AI First**
Repositorio: `andresforeroh11-ui/truora-support-copilot` · Video: _[enlace]_

## 1. Proceso de pensamiento

**El rol.** El Líder de Soporte de Truora tiene que sostener los SLA de clientes B2B que integran por API en 5 países, escalar a Ingeniería con la información mínima, convertir tickets repetidos en mejoras y hacerlo con automatización e IA, sin crecer la plantilla al mismo ritmo.

**El problema que elegí.** La mayor parte del juicio diario del líder se va en decidir qué atender primero y qué escalar. En Truora eso tiene una particularidad: una parte del volumen no es falla propia. Son rechazos explicables (`blurry_image`, `process_started_late`), fuentes del gobierno caídas (`government_database_unavailable`), decisiones de Meta sobre líneas de WhatsApp o errores de la integración del cliente. Escalar eso a Ingeniería es ruido, y enterarse de una fuente caída cuando el cliente ya abrió ticket es tarde.

**Cómo lo validé.** Casi no hay reseñas públicas de Truora (6 en Capterra), así que usé su documentación técnica (catálogo de motivos de rechazo, reglas de WhatsApp, migración de `user_phone_number`, Hooks, revisión manual), su página de estado y sus vacantes. Los dolores del agente son hipótesis basadas en información pública, no datos internos.

**La solución.** Un copiloto que, por cada ticket, decide **de dónde viene la falla** antes de decidir qué hacer: clasifica origen y severidad, redacta la primera respuesta con la base de conocimiento, arma la ficha para Ingeniería solo si el origen es la plataforma, detecta incidentes (3+ tickets iguales en 30 min) diciendo si parecen fuente externa o plataforma, responde preguntas del líder sobre un caso y le entrega un resumen cada mañana. **Nada llega al cliente sin aprobación humana**, porque es un negocio de identidad y datos personales.

**Descartado:** respuesta automática sin humano (riesgo); tablero en Lovable (tiempo: el bot de Telegram cubre la interfaz); agrupar feedback para Producto como agente principal (menos medible en 4 días que la precisión de un clasificador).

**Stack:** formulario de n8n (entrada) → 4 workflows de n8n (A triage, C aprobación y consultas, D resumen diario, E evaluación) → OpenAI gpt-4o-mini → Supabase (tickets, salidas, prompts versionados, métricas) → bot de Telegram y correo.

## 2. Prompts y por qué

| Prompt | Hace | Decisión de diseño |
| --- | --- | --- |
| **P1 Clasificador** | Origen → severidad → ruta, en JSON | Temperatura 0, salida validada por esquema; la decisión en 3 pasos separa *a quién le toca* de *cuánto duele*; "un origen externo no baja la severidad"; ejemplos few-shot con códigos reales de la documentación |
| **P2 Redactor** | Respuesta o comunicado proactivo | Solo usa la KB y el motivo de rechazo; pide datos en vez de inventar; nunca dice "fraude" ni pide datos personales completos, solo IDs de proceso |
| **P3 Ficha de escalamiento** | Ficha para Ingeniería | Solo corre si el origen es la plataforma (o indeterminado P1/P2); hipótesis verificable con su certeza y 3–5 cosas concretas que revisar |
| **P4 Resumen del líder** | Resumen de 24 h | Las cifras y el destino de cada patrón los calcula SQL; la IA solo redacta |
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

Llevé una bitácora de 22 retos (`docs/bitacora_retos.md`). Los que más enseñan:

1. **Verificar antes de afirmar.** Un dato sobre reintentos de webhooks venía de una página de Truora que ya no existe (404). Lo retiré de la KB en vez de afirmarlo. La API key la probé con una llamada real antes de concluir que no servía.
2. **Medir y parar a tiempo.** La corrida 1 escalaba 4 casos que no eran de Ingeniería. Agrupé los errores en patrones, versioné P1-v3 y bajé a 1 (ver tabla).
3. **Separar prueba de operación.** Las 60 clasificaciones de la evaluación disparaban alertas falsas de incidente. Creé una vista que excluye el set de prueba.
4. **Quitarle decisiones a la IA.** P4 mandó una falla de plataforma a "Comunicación proactiva". En lugar de alargar el prompt, el destino lo calcula SQL con una regla fija y el modelo solo redacta.
5. **Un incidente, un renglón.** La segunda oleada de la misma caída creaba otro incidente. Ahora el ticket se suma al incidente abierto sin repetir la alerta.
6. **El control humano debe mostrar qué se aprueba.** Al usar el bot de verdad, "Editar" envió al cliente una pregunta como si fuera la respuesta. Ahora el texto editado se muestra completo y solo sale con "Enviar al cliente".

**Lo que todavía no sé hacer bien:** desplegar esto sobre un help desk real y medir deriva del modelo en producción. Es el siguiente paso: conectar el help desk, validar con tickets reales anonimizados, consultar status.truora.com para confirmar fuentes caídas y medir el costo de P2–P5.
