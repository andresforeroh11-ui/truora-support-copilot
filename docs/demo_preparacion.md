# Preparación de la demo

## Antes de grabar

- [ ] **Cerrar los incidentes de prueba abiertos.** Hoy hay 2 abiertos (identidad, Colombia). Mientras sigan abiertos, un ticket igual se suma al incidente sin repetir la alerta. La demo usa México y Chile para no depender de esto, pero conviene dejar la base limpia:
  ```sql
  update incidentes set estado = 'cerrado' where estado = 'abierto';
  ```
- [ ] **Publicar el workflow A.** Despublicado, el formulario solo funciona en modo prueba desde el editor. Publicado, tiene una URL fija para grabar.
- [ ] Confirmar que **C** está publicado (botones, correos y consultas). No probarlo desde el editor.
- [ ] Tener a la mano un **resumen diario reciente** de D en Telegram (con las 4 gráficas) para el bloque 5. Si hace falta uno nuevo, ejecutar D manualmente.
- [ ] Ensayo completo con estos mismos tickets. Después, cerrar el incidente de México que se creó en el ensayo para que la alerta vuelva a salir en la toma buena.
- [ ] Ventanas listas: formulario de A, Telegram (escritorio o web), buzón de prueba del correo y Supabase en `v_metricas_corrida`.

## Tickets de la demo

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

Si en el ensayo algún ticket sale distinto, se anota y se decide: si el resultado es defendible, se muestra tal cual; un modelo que acierta el 87 % no tiene por qué acertar siempre, y explicarlo suma.
