# Evaluación del clasificador P1

**Set:** 30 tickets sintéticos con severidad y origen etiquetados a mano (revisados por Andrés). **Modelo:** gpt-4o-mini, temperatura 0, salida JSON validada por esquema. **Cálculo:** las métricas salen de la vista SQL `v_metricas_corrida`; la IA no se califica a sí misma.

| Métrica | Corrida 1 (P1-v2) | Corrida 2 (P1-v3) | Meta |
| --- | --- | --- | --- |
| Precisión de severidad | 73,3% | **80,0%** | reportar |
| Precisión de origen | 66,7% | **86,7%** | reportar |
| P1 no detectados | 0 | **0** | 0 |
| Escalamientos innecesarios | 4 | **1** | 0 |
| JSON válido | 30/30 | 30/30 | 30/30 |

## Qué falló en la corrida 1 y qué cambió en v3

1. **Atribuía a la plataforma cambios del cliente** (T15, T26, T29, T37: 4 escalamientos innecesarios). → Regla: si la falla empieza tras un cambio del cliente o el código es de configuración, el origen es `integracion_cliente`; "les falla a todos" no basta para decir `truora`.
2. **Inflaba la severidad** (parciales como P1, casos puntuales como P2). → Límites explícitos P1/P2/P3 y la regla "ante la duda, sube" quedó solo para P1 vs P2.
3. **Adivinaba el origen en vez de decir `indeterminado`** (T03, T10, T21). → Casos obligatorios de `indeterminado`.
4. **Consultas generales como `no_aplica`** (T09, T20). → `no_aplica` solo para facturación/cuenta.
5. Dos ejemplos few-shot nuevos (cambio del cliente, falla parcial), sin copiar tickets del set.

## Errores que quedan en la corrida 2 (9 de 60 decisiones)

- **Severidad sigue alta en 5 casos** (T12, T23, T29, T36, T37): el modelo lee "todos los usuarios de la app" como P1 y casos puntuales como P2. El error es conservador: ningún P1 real se perdió.
- **1 escalamiento innecesario** (T15: CURP lento en sandbox clasificado como plataforma P1).
- **T03** sigue como `usuario_final` en vez de `indeterminado`.
- **T09 y T20** siguen como `no_aplica`: la etiqueta de consulta es discutible y no se forzó.

## Limitación honesta

Ajustar el prompt mirando los mismos 30 tickets puede sobreajustar. Antes de producción: un set de validación separado (los 10 tickets no etiquetados o tickets reales anonimizados) y medir de nuevo.
