# Casos de la demo

Los 4 tickets que se envían en el video por el formulario del flujo A. Clientes ficticios; sirven para reproducir la demo. Para que la alerta de incidente salga, MX-1 a MX-3 deben enviarse con menos de 30 minutos entre el primero y el tercero y sin un incidente igual abierto.

## Tickets

Clientes ficticios. Enviar MX-1, MX-2 y MX-3 con menos de 30 minutos entre el primero y el tercero.

**MX-1**
- Cliente: `Financiera Nopal (ficticio)`
- País: `MX`
- Asunto: `Validaciones de INE rechazadas en producción`
- Descripción: `Desde las 10:05 todas las validaciones de INE salen declined con government_database_unavailable. Estamos en producción y el onboarding de nuevos clientes está detenido. Ejemplo de proceso: IDP-mx-demo-0001.`

**MX-2**
- Cliente: `Crédito Ágil (ficticio)`
- País: `MX`
- Asunto: `Consulta a RENAPO no responde`
- Descripción: `Hace 20 minutos que la validación de CURP no responde y los procesos quedan rechazados con government_database_unavailable. Producción, tenemos solicitudes en cola. Proceso de ejemplo: IDP-mx-demo-0002.`

**MX-3**
- Cliente: `Seguros Pacífico (ficticio)`
- País: `MX`
- Asunto: `Usuarios no pueden terminar el registro`
- Descripción: `Ningún usuario ha podido terminar el registro desde esta mañana: la validación de identidad falla con government_database_unavailable en todos los intentos. Ambiente productivo. Proceso: IDP-mx-demo-0003.`

**CL-1**
- Cliente: `Retail Andes (ficticio)`
- País: `CL`
- Asunto: `No llega el webhook de proceso terminado`
- Descripción: `Desde ayer a las 18:00 no recibimos el webhook de proceso terminado en producción para ningún usuario. Nuestro endpoint responde 200 a pruebas manuales y no cambiamos la URL ni las reglas de Hooks. Otros eventos sí llegan. Ejemplo: IDP-cl-demo-0042.`

## Resultado esperado

| Ticket | Origen | Severidad | Acción | Qué se ve |
| --- | --- | --- | --- | --- |
| MX-1 | fuente externa (gobierno) | P1 | comunicado proactivo | Mensaje con borrador de comunicado y 3 botones |
| MX-2 | fuente externa (gobierno) | P1 o P2 | comunicado proactivo | Mensaje con borrador |
| MX-3 | fuente externa (gobierno) | P1 | comunicado proactivo | Mensaje con borrador **y alerta de incidente: fuente externa** |
| CL-1 | plataforma (Truora) | P1 o P2 | escalar a Ingeniería | Mensaje con ficha P3 y botón *Confirmar escalamiento* |

**Ensayo del 28 oct:** 4 de 4 como se esperaba. MX-1 a MX-3: fuente externa, P1, comunicado proactivo, confianza 0,90; al tercero se creó el incidente "fuente externa · identidad · MX". CL-1: plataforma, P1, escalar a Ingeniería, confianza 0,80, con ficha P3.
