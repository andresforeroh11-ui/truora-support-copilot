# Guion del video (≤ 5:00)

Meta: **4:40**. Unas 570 palabras de narración a ritmo normal. Se graba **por bloques** y se une al final; la demo (bloque 4) se graba aparte porque la API tarda unos segundos por ticket. Esas esperas se cortan en edición.

Antes de grabar: completar `docs/demo_preparacion.md`.

| Bloque | Tiempo | Requisito Truora |
| --- | --- | --- |
| 1. Problema | 0:00–0:25 | 1a, 1b |
| 2. Configuración | 0:25–1:15 | 4a |
| 3. El paso de IA | 1:15–2:10 | 4b |
| 4. Demo | 2:10–3:50 | 4c |
| 5. Resultados y cierre | 3:50–4:40 | Uso de IA, autonomía |

---

## 1. Problema · 0:00–0:25

**Pantalla:** tu cara o el diagrama del README.

> Soy Andrés Forero, aplico a Líder de Soporte Operations. En un soporte como el de Truora, muchos tickets no son fallas de Truora: son rechazos explicables, fuentes del gobierno caídas, decisiones de Meta o la integración del cliente. Construí un copiloto que separa eso en segundos, para que Ingeniería solo reciba lo que es suyo y el cliente se entere antes de preguntar.

## 2. Configuración · 0:25–1:15

**Pantalla:** diagrama del README → lista de los 4 workflows en n8n → workflow A abierto → tablas en Supabase.

> El ticket entra por un formulario que simula el portal de soporte. Hay cuatro workflows en n8n. A hace el triage: guarda el ticket, lo clasifica, redacta, arma la ficha si hay que escalar y detecta incidentes. C atiende los botones del bot de Telegram, los correos y las consultas del líder. D envía el resumen de cada mañana. E corre la evaluación.
>
> Todo queda en Supabase: tickets, clasificaciones, borradores, escalamientos, incidentes y cada correo enviado. Los prompts también viven ahí, versionados: cambiar uno no requiere tocar n8n. Nada llega al cliente sin que una persona lo apruebe.

## 3. El paso de IA · 1:15–2:10

**Pantalla:** tabla `prompts` (P1-v3 activo, P1-v2 inactivo) → texto de P1 con los 3 pasos → nodo de OpenAI en A → JSON de salida de una ejecución.

> El modelo es gpt-4o-mini de OpenAI, con cinco prompts y un solo trabajo cada uno. P1 clasifica en tres pasos: primero el origen de la falla, es decir, a quién le toca resolver; después la severidad, por impacto en el cliente; y al final la ruta. Un origen externo no baja la severidad: si la Registraduría se cae en producción, para el cliente sigue siendo P1.
>
> Devuelve JSON validado contra un esquema, con temperatura cero y ejemplos con códigos reales de la documentación de Truora. P2 redacta solo con la base de conocimiento: 145 motivos de rechazo y seis artículos. P3 arma la ficha para Ingeniería con una hipótesis verificable. Y en el resumen diario, las cifras y los destinos los calcula SQL; la IA solo redacta.

## 4. Demo · 2:10–3:50

**Pantalla:** navegador con el formulario a la izquierda y Telegram a la derecha.

**4a · Ticket de fuente externa (MX-1).** Enviar el formulario.

> Un cliente en México reporta que todas las validaciones fallan con government_database_unavailable. El agente lo clasifica: fuente externa del gobierno, P1, sin escalar a Ingeniería. En lugar de una respuesta individual, propone un comunicado proactivo para todos los clientes del país.

**4b · Tickets MX-2 y MX-3.** Enviarlos seguidos; mostrar la alerta.

> Llegan dos tickets más con el mismo patrón. Al tercero, el líder recibe la alerta: posible incidente de fuente externa, con los números de caso y desde cuándo ocurre. La acción es confirmar en status.truora.com y comunicar, no escalar.

**4c · Ticket de webhook (CL-1).** Enviar; mostrar ficha y botón.

> Ahora un cliente en Chile: el webhook de proceso terminado no llega en producción, su endpoint responde bien y no cambiaron nada. Aquí sí el origen es la plataforma: el agente arma la ficha para Ingeniería, con impacto, evidencia, hipótesis y qué revisar. El escalamiento sale solo si el líder lo confirma.

**4d · Aprobar y consultar.** Tocar *Aprobar y enviar* en MX-1, mostrar el correo; escribir `caso <número de CL-1> ¿ya se escaló?`.

> Apruebo el comunicado y sale el correo. Y si quiero saber cómo va un caso, le pregunto al bot: responde solo con los datos de ese caso.

## 5. Resultados y cierre · 3:50–4:40

**Pantalla:** `v_metricas_corrida` en Supabase → resumen diario en Telegram con las 4 gráficas.

> Lo medí contra 30 tickets etiquetados a mano antes de correr el agente. En la primera corrida, 73 % de precisión en severidad, 67 % en origen y cuatro escalamientos innecesarios. Agrupé los errores, ajusté el prompt y en la segunda: 80 % y 87 %, un solo escalamiento innecesario y ningún P1 perdido. No hice una tercera corrida para no sobreajustar al mismo set.
>
> Cada mañana el líder recibe esto: SLA en riesgo, incidentes y a dónde llevar cada patrón. Lo construí con apoyo de Claude Code. El siguiente paso es conectarlo al help desk real y validarlo con tickets anonimizados. Gracias.

---

## Reglas de grabación

- 1080p, Loom u OBS. Zoom del navegador al 110–125 % para que se lea el texto.
- No mostrar en pantalla: credenciales de n8n, la `service_role` de Supabase, el token del bot ni correos personales.
- Si un bloque se pasa de tiempo, recortar el bloque 2: los bloques 4 y 5 son los que más pesan.
- Revisar el corte final con cronómetro. Si pasa de 5:00, no se envía.
