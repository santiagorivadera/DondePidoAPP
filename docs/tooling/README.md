# Herramientas de DondePido

Instalación autorizada el 2026-11-06. No se creó la aplicación ni se ejecutaron
auditorías, migraciones, despliegues o conexiones a nuevos proyectos Supabase.

## Inventario
| Herramienta | Instalación | Verificación |
| --- | --- | --- |
| Playwright CLI 0.1.23 | tooling/node_modules + skill local en .agents/skills/playwright-cli | Abrió y cerró Chrome headless en about:blank |
| Supabase plugin | Plugin de Codex previamente instalado y habilitado; skills supabase y supabase-postgres-best-practices ya disponibles | Inventario del gestor de plugins; sin consultas a proyectos remotos |
| Context7 | MCP HTTPS en .codex/config.toml | Initialize, tools/list y consulta pública de Next.js correctos |
| SkillUI 1.3.4 | tooling/node_modules | CLI y extracción de CSS sintético a DESIGN.md y paquete .skill correctos |
| Strix 1.7.0 | Entorno Python aislado tooling/.venv-strix; skill local penetration-testing-with-strix | El 2026-11-11: --version correcto y pip check sin dependencias rotas; versiones guardadas en requirements-strix.lock.txt |

## Uso desde la raíz
```powershell
.\tooling\playwright-cli.cmd --help
.\tooling\skillui.cmd --help
.\tooling\strix.cmd --version
```

No hace falta instalar ejecutables globales. Para una sesión de shell que use los
comandos sin ruta, agregar temporalmente `tooling` al PATH de esa sesión. Las skills
upstream usan nombres sin ruta: los agentes deben usar los wrappers locales arriba.
Los skills estarán disponibles en el próximo turno que actualice su catálogo;
iniciar un chat nuevo en la raíz asegura la carga del MCP y la configuración.

Context7 usa acceso público sin clave, con los límites del proveedor. Si exige
autenticación más adelante, usar OAuth o una variable segura, nunca escribir claves
en el TOML versionado. Enviar solo preguntas técnicas sin datos privados.

Supabase se reutiliza desde el plugin de Codex; no se instaló una segunda copia
ni un segundo MCP. No se seleccionó o creó una base de datos para DondePido.

## Dependencias y reproducción
Se usó Node 24.18.1. Las dos dependencias directas npm están fijadas en
`tooling/package.json`, con árbol e integridades en `tooling/package-lock.json`.
Reinstalación: `npm ci --prefix tooling --ignore-scripts`.
Playwright detectó el Chrome ya instalado; no se descargaron navegadores extra.
La versión CLI publicada utiliza Playwright 1.65.0-alpha-2026-10-30 internamente.

SkillUI upstream introducía nueve alertas de dependencias. `npm audit fix` no las
resolvió. Se fijaron overrides: simple-git 4.0.2, glob 14.0.4 y esbuild 0.28.2.
Después: npm audit sin vulnerabilidades registradas y prueba de extracción estática
correcta. Son overrides locales con cambios de versión mayor; no se verificaron
los modos remoto, clonación o ultra. No usar esos modos sin validación previa.
La ausencia de alertas npm no equivale a una auditoría de seguridad completa.

Strix usa Python 3.12.14 del runtime existente de Codex, sin modificarlo. El venv
no se versiona y depende de ese intérprete en esta máquina. Con Python >=3.12:
```powershell
python -m venv tooling/.venv-strix
tooling/.venv-strix/Scripts/python.exe -m pip install -r tooling/requirements-strix.lock.txt
```

## Límites de Strix
Docker Desktop está instalado pero su motor Linux no estaba activo durante la
preparación. No se configuró proveedor LLM ni clave para Strix, no se descargó
su imagen de sandbox y no se ejecutó un escaneo. El modelo de Strix es independiente
del selector de Codex y puede generar cargos del proveedor externo.
Antes de un pentest: definir objetivo autorizado, alcance, entorno de pruebas,
presupuesto y modelo; activar Docker y configurar acceso al proveedor de forma segura.
No usar el servicio cloud ni subir código como fallback automático. Los targets
locales pueden montarse con escritura: usar un checkout de prueba cuando corresponda.

Se instaló solo la skill general de Strix para evitar cargar nueve descripciones
solapadas. Sus ejemplos no constituyen autorización para escanear o subir código.
SkillUI es una CLI generadora: no se inventó ni se activó un sistema de diseño
extraído del proyecto vacío. Sus resultados futuros deberán respetar el kit aprobado.

## Fuentes
- https://github.com/microsoft/playwright-cli
- https://github.com/supabase-community/supabase-plugin
- https://github.com/upstash/context7/blob/master/docs/clients/codex.mdx
- https://github.com/amaancoderx/npxskillui
- https://github.com/usestrix/strix
- https://pypi.org/project/strix-agent/1.7.0/

Skill Strix fijada al commit `06015506625a78b981ae0b34be40239fc1b389be` mediante
el instalador de skills de Codex. Playwright skill procede del paquete npm fijado.
