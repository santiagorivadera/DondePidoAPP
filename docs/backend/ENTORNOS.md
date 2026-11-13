# Entornos de Supabase

## Propósito y estado

El archivo versionable `supabase/config.toml` contiene la configuración de la pila local. Se generó con Supabase CLI 2.117.0 instalado en este equipo y se ajustó para usar el identificador local `dondepido-local` y puertos propios. El CLI muestra que existe una versión posterior disponible. Revisar el changelog y la compatibilidad antes de actualizarlo.

La API local expone explícitamente `public` y `graphql_public`. El esquema interno `dondepido` no está en `api.schemas` ni en `api.extra_search_path`. Mantenerlo fuera de esas listas al revisar la configuración.

El repositorio Git local ya está inicializado en la rama `main`, sin commits. Docker Desktop se lanzó mediante su CLI oficial y el motor Linux quedó accesible. `supabase start` inició correctamente el proyecto `dondepido-local`. Tras habilitar localmente confirmación por correo y MFA TOTP, se reinició solo este proyecto preservando su volumen. La base, Auth, API, Storage y Studio locales responden. Database verificó las dos migraciones B1 en PGlite y QA informó 36/36 pruebas pgTAP y lint correctos. Este directorio no contiene un enlace a un proyecto remoto.

## Entornos

| Entorno | Uso | Datos y credenciales |
| --- | --- | --- |
| Local | Desarrollo y pruebas de integración | Pila local activa y datos ficticios. Los valores de conexión se consultan localmente con el CLI. No guardar archivos `.env` con valores reales en Git. |
| Demo/validación remota | Demostraciones y aceptación con datos ficticios | Requiere un proyecto Supabase separado y configuración/credenciales separadas de producción. No enlazar ni desplegar desde este scaffold local sin autorización específica. |
| Producción | Operación del producto | El Tech Lead verificó un proyecto existente en estado `main / PRODUCTION`. Este scaffold no incluye su referencia, enlace, credenciales ni cambios. No ejecutar comandos remotos sobre él. |

Al 12 de noviembre de 2026, el proyecto alojado DondePido está en una organización gratuita. Santiago prevé trasladarlo más adelante a su organización paga, que identificó como «CyDsyistems». Al preparar el traslado, verificar el nombre y el identificador de la organización de destino en el panel. El traslado sigue pendiente y es independiente del entorno remoto de demo.

El proyecto indicado por `project_id` distingue la pila local en el host. No es una referencia al proyecto Supabase alojado. `.env` y `.env.*` están excluidos por el `.gitignore` raíz, con excepción de `.env.example`; publicar allí solo nombres de variables y placeholders.

## Puertos locales

La configuración usa el bloque `55420–55429` para base, API, Studio, correo de prueba, analítica y pooler, y `58083` para el inspector de Edge Runtime. Se eligió después de comprobar que no había listeners en esos puertos. Si otra aplicación los ocupa más adelante, detener la pila local antes de cambiar la configuración y actualizar también los valores de entorno locales de la aplicación.

| Servicio | Puerto local |
| --- | ---: |
| Base principal | 55422 |
| Base shadow de migraciones | 55420 |
| API local | 55421 |
| Studio | 55423 |
| Bandeja local de correo | 55424 |
| Analítica | 55427 |
| Pooler, inicialmente deshabilitado | 55429 |
| Inspector de Edge Runtime | 58083 |

El stack previo de otro proyecto (`ae-phonestore`) ocupa los puertos estándar 54321/54322. La configuración de DondePido utiliza su propio bloque de puertos y permite coexistencia local. No administrar ni detener el otro proyecto desde esta configuración. El contenedor local de Vector aparece reiniciándose, pero no bloqueó las pruebas ni la disponibilidad de los servicios requeridos por B1.

## Flujo local

1. Revisar Docker Desktop y los puertos requeridos.
2. Desde la raíz, arrancar o verificar solo el proyecto local con `supabase start` y `supabase status`.
3. Aplicar y revisar migraciones solo con la secuencia coordinada por Database. No apuntar `db push`, `link` ni comandos remotos a producción.
4. Mantener datos locales ficticios. No copiar registros personales o comerciales de producción.

## Cambios y recuperación

Versionar la configuración, SQL, pruebas y documentación en Git. Mantener copias del código fuente fuera del workspace en `C:/Proyectos/DondePidoAPP-backups`, limitadas a fuentes, SQL, tests y docs. No incluir datos, volúmenes, archivos `.env`, credenciales ni dumps de producción en ese respaldo. Probar cada migración en local y en el entorno de validación aislado antes de una liberación autorizada. La migración a producción requiere revisión de Database y QA, autorización, respaldo verificado y un plan de recuperación que contemple cambios irreversibles y compatibilidad de versiones. Un rollback de aplicación por sí solo no revierte cambios de datos.

La base local incluye el núcleo y el alta comercial. El registro usa correo y contraseña, la verificación del teléfono usa un SMS simulado en Mailpit y las acciones de administración requieren MFA. El [flujo de alta local](ALTA_LOCAL.md) documenta el arranque de Next.js y las pruebas de base y de punta a punta.

Se creó una copia revisable previa al runtime en `C:/Proyectos/DondePidoAPP-backups/2026-11-12-B1-pre-runtime`. Incluye `docs/`, `supabase/config.toml` y las dos migraciones SQL. Excluye Git, datos, volúmenes, `.env`, credenciales e instalaciones. Esta copia no es un respaldo de base de datos ni restaura la pila local.

En producción, el respaldo de PostgreSQL no incluye los objetos guardados en Supabase Storage. Antes del lanzamiento hay que definir una estrategia separada de copia/restauración para imágenes y archivos. Verificar restauraciones en un entorno aislado y documentar pérdida de datos admisible y tiempo de recuperación; no se han acordado objetivos RPO/RTO.

## Referencias

- [Referencia de configuración de Supabase CLI](https://supabase.com/docs/guides/local-development/cli/config)
- [Flujo de desarrollo local de Supabase](https://supabase.com/docs/guides/local-development)
- [Respaldos de base de datos de Supabase](https://supabase.com/docs/guides/platform/backups)
- [Changelog de Supabase](https://supabase.com/changelog.md)
