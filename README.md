# Truora Support Copilot

Agente de IA de triage y escalamiento para un equipo de soporte B2B multi-país (identidad, background checks, firma electrónica y WhatsApp). Prueba técnica PT1 – AI First, vacante Líder de Soporte Operations (Hispam).

> En construcción. Solo datos sintéticos: ningún dato real de clientes ni de usuarios finales.

## Qué hace
1. Recibe un ticket (formulario de n8n).
2. Clasifica con IA: origen de la falla, severidad P1–P4, acción sugerida (JSON validado).
3. Redacta el borrador de respuesta o comunicado proactivo y, solo si el origen es la plataforma, la ficha de escalamiento a Ingeniería.
4. Detecta posibles incidentes (3+ tickets del mismo patrón) e indica si parece falla de plataforma o de fuente externa.
5. Un humano aprueba en Telegram antes de que algo llegue al cliente.

## Stack
n8n (orquestación) · OpenAI API (procesamiento) · Supabase/Postgres (datos) · Telegram (interfaz)

## Estructura
| Carpeta | Contenido |
| --- | --- |
| `sql/` | Esquema de la base de datos y cargas iniciales |
| `data/` | Tickets sintéticos y base de conocimiento |
| `prompts/` | Prompts P1–P4 |
| `workflows/` | Workflows de n8n exportados (sin credenciales) |
| `docs/` | Notas de la prueba y resultados de evaluación |

## Seguridad
Las credenciales viven solo en n8n. Nunca se suben claves a este repositorio.
