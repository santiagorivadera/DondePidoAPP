# Equipo multiagente DondePido

## Uso
Abrir `C:\Proyectos\DondePidoAPP` como proyecto en Codex e iniciar una sesión allí.
La sesión inicial de preparación se inició en el kit visual. Una configuración
local nueva no cambia retroactivamente los permisos o modelos de chats ya iniciados.
Desde PowerShell también se puede iniciar con:

```powershell
codex -C C:\Proyectos\DondePidoAPP
```

El principal actúa como Tech Lead. Selecciona solo los especialistas necesarios,
asigna objetivo y archivos exclusivos, acuerda contratos, espera resultados,
revisa y presenta una única respuesta al usuario. Hay seis perfiles disponibles,
pero como máximo tres subagentes concurrentes. Modelos iniciales por responsabilidad:

| Agente | Modelo | Razonamiento |
| --- | --- | --- |
| Tech Lead | gpt-6.1-sol | medium |
| Frontend & UI/UX | gpt-6.1-sol | low |
| Backend & Supabase | gpt-6.1-sol | medium |
| Database & PostgreSQL | gpt-6.1-sol | medium |
| QA & Security | gpt-6.1-sol | medium |
| DevOps & Deployment | gpt-6-luna | high |
| Documentation & Architecture | gpt-6-luna | high |

Los subagentes genéricos tienen Luna/high como base. El modelo del Tech Lead puede
ser reemplazado por una elección explícita en el selector de la aplicación.
Cada especialista tiene modelo y esfuerzo explícitos en su TOML. Para nuevas
decisiones críticas, el Lead aplica la regla de escalamiento de AGENTS.md; no se
presume que una opción de spawn reemplace los valores explícitos de un perfil.
La documentación de decisiones ya tomadas y preparación rutinaria de DevOps van
a Luna; diseño transversal o permisos nuevos requieren Sol y revisión del Lead.

Se priorizan encargos acotados, cero a dos delegaciones habituales, búsquedas
dirigidas y reportes breves. No hay un presupuesto duro de tokens configurado ni
una estimación porcentual de ahorro: se debe medir consumo y retrabajo con tareas
reales antes de optimizar más. No se modifica el modelo global del usuario.

El alcance inicial está limitado a preparar el equipo. La siguiente instrucción
de desarrollo del usuario habilitará ese trabajo específico; no autoriza por sí
sola producción, publicaciones o cambios remotos ajenos al encargo.

## Configuración y permisos
`AGENTS.md` define arquitectura, responsabilidades y coordinación.
`.codex/config.toml` habilita multiagente y establece
`agents.max_concurrent_threads_per_session = 3`, excluyendo al principal.
Los seis TOML bajo `.codex/agents/` son perfiles autocontenidos descubiertos por
Codex; su identidad está en `name` y sus instrucciones en `developer_instructions`.

Se solicita `workspace-write`, red de shell deshabilitada y aprobación
`on-request` para sesiones que respeten esta configuración. El host o una elección
explícita de permisos puede prevalecer. La sesión de preparación tenía acceso
completo y política `never`: no se afirma que estos archivos la hayan restringido.
Los especialistas heredan permisos del principal. Un perfil no crea un sandbox
independiente. Las restricciones del shell no equivalen a bloquear conectores MCP.
No se configuraron conexiones ni credenciales de GitHub, Vercel o Supabase.

## Verificación reproducible
Ejecutar desde PowerShell:

```powershell
& C:\Proyectos\DondePidoAPP\.codex\verify-team.ps1
```

El script usa el propio Codex para validar estrictamente la configuración y
construir el contexto sin ejecutar inferencia. Comprueba que los seis nombres
aparezcan en el catálogo real de especialistas y que se cargue AGENTS.md.
Verifica el valor de concurrencia; no es una prueba de saturación de cuatro agentes.
Consulta además el catálogo de modelos y comprueba compatibilidad de cada esfuerzo.
No imprime el contexto completo, que puede incluir configuración personal.

Prueba de delegación repetible en una sesión iniciada en esta raíz:

> Como Tech Lead, delegá en qa_security la revisión de seguridad de la configuración
> y en documentation_architecture la revisión de roles y coordinación. Solo lectura,
> sin servicios externos ni otros subagentes. Esperá ambos resultados y consolidalos.

## Fuentes y alcance de inspección
La carpeta de aplicación estaba vacía: no había Git, código, manifiestos,
dependencias, tests ni configuración local anterior. El kit visual se conserva.
Se recuperó de la conversación previa «Crear equipo multiagente» el stack y
el esquema de orquestador con seis especialistas; la herramienta devolvió el
mensaje largo truncado. No se afirma haber recuperado literalmente todo el prompt.
Las reglas se concretaron con la solicitud actual y el fragmento disponible.

Referencias oficiales consultadas el 2026-11-06:
- [Especialistas de Codex](https://learn.chatgpt.com/docs/agent-configuration/subagents)
- [Configuración de Codex](https://learn.chatgpt.com/docs/config-file/config-reference)

El informe de la ejecución inicial está en `VERIFICATION.md`.
