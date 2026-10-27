# Base de conocimiento — 6 artículos

Redactados a partir de la documentación pública de Truora (consultada el 27 oct 2026). Son la única fuente que el prompt P2 puede usar para responder. Se cargan en la tabla `kb_articulos` con `sql/02_kb_articulos.sql`.

---

## 1. `fuente-externa-caida` — Fuente del gobierno no disponible o lenta
**Producto:** identidad, background_check · **Origen:** fuente_externa_gobierno

- Las validaciones de documento y los background checks consultan bases externas (Registraduría, RENAPO/CURP, Receita Federal, RENIEC, Registro Civil, entre otras).
- Si la fuente no responde, el proceso puede declinarse con `government_database_unavailable` o el check puede demorarse.
- El Status Monitor de checks muestra por país cinco estados: rendimiento degradado, interrupción parcial, interrupción mayor, en mantenimiento y obsoleta.

**Qué hace soporte**
1. Confirmar el estado de la fuente en el Status Monitor y en status.truora.com.
2. No escalar a Ingeniería: la falla no es de la plataforma.
3. Si afecta a varios clientes del mismo país, enviar un comunicado proactivo con la hora de la próxima actualización.
4. Cuando la fuente se restablezca, reintentar los procesos afectados. Si el cliente tiene revisión manual contratada, el caso puede pasar a revisión.

**Qué decir al cliente:** no es un error de su integración ni del usuario. Explicar que es una fuente externa, sin culpar a la entidad y sin prometer hora de solución.

Fuentes: dev.truora.com/guides/checks_continuous_and_status/ · dev.truora.com/guides/declined_reasons_details/ · status.truora.com

---

## 2. `reglas-meta-whatsapp` — Calidad, límites y plantillas de WhatsApp
**Producto:** whatsapp · **Origen:** meta_whatsapp

- Meta califica la calidad de la línea con la reacción de los usuarios en los últimos 7 días (bloqueos y reportes). Las interacciones recientes pesan más. Hay tres niveles: alta, media y baja.
- **Límites:** 250 conversaciones iniciadas por el negocio en 24 h al inicio, y 1K con verificación del negocio o buen historial. Los niveles de 10K, 100K e ilimitado suben automáticamente si la calidad es media o alta y en los últimos 7 días se usó al menos la mitad del límite actual. El aumento se aplica tras 24 h.
- **Calidad baja sostenida** durante 7 días: Meta puede reducir el límite de inmediato y, si persiste, suspender el envío. Los reportes graves de spam pueden desactivar la cuenta.
- **Plantillas:** deben estar preaprobadas, no pueden ser promocionales y Meta puede rechazarlas en cualquier momento.

**Qué hace soporte:** confirmar el estado y el límite actual de la línea, y el nombre de la plantilla afectada. Una línea suspendida en producción es P1; una plantilla crítica rechazada o un límite reducido es P2. Estas son decisiones de Meta, no fallas de Truora.

**Cómo recuperar la calidad:** enviar solo a usuarios con consentimiento explícito, respetar las bajas de inmediato, personalizar los mensajes y reducir su frecuencia, completar la verificación del negocio y revisar que las plantillas cumplan la política de WhatsApp.

Fuente: dev.truora.com/guides/waba_rules/

---

## 3. `migracion-bsuid` — Retiro de `user_phone_number` en Flowbuilder
**Producto:** whatsapp · **Origen:** integracion_cliente

- WhatsApp habilitó nombres de usuario opcionales. Si un usuario los activa, su número deja de compartirse con la empresa, salvo que haya interactuado con ella en los últimos 30 días o que esté en su agenda.
- **Desde el 14 de agosto de 2026**, Flowbuilder no permite guardar flujos que usen `user_phone_number`. Los flujos ya publicados siguen funcionando, pero la variable puede llegar vacía.
- **BSUID:** identificador único del usuario por cuenta de WhatsApp Business. En Flowbuilder aparece como *WhatsApp User ID*; en Webhooks/Automations, como `process.business_scoped_user_id`.
- En Webhooks/Automations, `process.user_phone_number` se llena con este orden: número enviado por Meta, número capturado y verificado en el flujo, o vacío. No está garantizado.

**Pasos para el cliente**
1. Ubicar los flujos que usan `user_phone_number`, en variables globales y en bloques.
2. Agregar una captura explícita del teléfono: validación por OTP (recomendada si alimenta reglas), formulario de WhatsApp Flow o pregunta abierta de tipo teléfono.
3. Cambiar reglas y automatizaciones para que usen WhatsApp User ID o `process.business_scoped_user_id`.
4. Probar con una cuenta que tenga el número privado.

Fuente: dev.truora.com/guides/migration_user_phone_number_deprecation/

---

## 4. `api-key-temporal` — `unauthorized`, API key temporal y cámara
**Producto:** identidad · **Origen:** integracion_cliente

- **El navegador muestra `unauthorized`:** el usuario abrió el proceso tarde y la API key temporal ya expiró. Hay que generar una nueva.
- **No se pueden consultar los datos de un proceso:** el ID es incorrecto, o el proceso se consulta con una API key temporal distinta a la que lo creó, o esa key ya expiró. Hay que consultar con la API key principal.
- **Buena práctica:** usar la API key temporal solo para que el usuario complete el proceso en el navegador, y la principal para leer resultados.
- **Cámara:** si el dispositivo o el navegador no permiten usarla, sugerir otro navegador o la cámara nativa. Si la falla afecta a todos los usuarios de una app (iframe o WebView), revisar que la integración del cliente conceda el permiso de cámara (ver motivo `unwanted_camera_permissions`).

**Qué hace soporte:** pedir un ID de proceso afectado y cómo y cuándo generan la API key temporal. No se escala salvo que el error persista con una key recién generada.

Fuentes: dev.truora.com/guides/common_errors/ · dev.truora.com/guides/declined_reasons_details/

---

## 5. `webhooks` — Webhooks que no llegan
**Producto:** identidad, firma, whatsapp · **Origen:** truora o integracion_cliente

- Los webhooks se configuran con una regla en Webhooks/Automations: producto, eventos (creación, éxito, fallo, sobrescritura, éxito de un paso), condiciones opcionales y la acción "Notification via webhook", con URL, método, credenciales y encabezados.
- El payload llega como JWT. El cliente debe validar la firma con su clave secreta.

**Ruta de diagnóstico antes de escalar**
1. **Alcance:** ¿un cliente o varios?, ¿desde cuándo?, ¿sandbox o producción?
2. **Evento:** con el ID de proceso, confirmar si el evento se generó.
3. **Entrega:** revisar el código de respuesta del endpoint del cliente y los intentos de entrega.
4. **Configuración:** regla activa, URL, método, credenciales, validación del JWT y cambios recientes del cliente.
5. **Hipótesis:** endpoint del cliente caído o mal configurado → `integracion_cliente`. Varios clientes sin webhooks a la vez, o eventos que no se generan → `truora`, y se escala con la ficha de P3.

Fuente: dev.truora.com/guides/web_webhooks/

---

## 6. `revision-manual` — Revisión manual con reloj de 24 horas
**Producto:** identidad · **Origen:** truora (si revisa Truora) o integracion_cliente (si revisa el cliente)

- Cuando el proceso automático detecta errores o inconsistencias, el caso pasa a revisión manual. La hace un equipo de Truora o el propio cliente desde la plataforma (Identidad digital → Revisión manual).
- El tiempo máximo es de **24 horas**. La plataforma muestra los documentos pendientes y un temporizador por solicitud.
- Si el plazo se vence, el proceso termina con `manual_review_not_performed` o `manual_review_expired`.

**Qué hace soporte:** confirmar quién hace la revisión. Pasadas 20 h, alertar al líder porque el SLA está en riesgo. Si el proceso venció, es un SLA incumplido: informar siempre al líder y reprocesar.

Fuentes: dev.truora.com/guides/manual_review/ · dev.truora.com/guides/declined_reasons_details/
