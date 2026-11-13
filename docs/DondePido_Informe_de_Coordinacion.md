# DondePido. — Informe de coordinación

**11 de noviembre de 2026** · [Especificación](DondePido_Analisis_y_Especificacion_del_Sistema.md) · [Matriz](DondePido_Matriz_de_Requerimientos.md).

El Tech Lead realizó la inspección inicial, contrastó fuentes públicas, repartió encargos acotados, integró los resultados y redactó los documentos. Los seis especialistas participaron mediante ejecuciones reales y entregaron sus informes de solo lectura. Se seleccionaron los tipos de agente por sus nombres y cada especialista contrastó el perfil TOML local. Se verificó la correspondencia de rol, modelo y esfuerzo configurados. La carga automática del archivo TOML por parte de la herramienta quedó sin verificar.

| Agente | Modelo y esfuerzo del perfil | Encargo y resultado integrado |
| --- | --- | --- |
| Documentation & Architecture (`documentation_architecture`) | `gpt-6-luna` · high | Revisó `AGENTS.md`, `docs/` y los antecedentes del kit. Identificó el vacío de especificación funcional, el carácter conceptual de las maquetas y las decisiones de producto faltantes. Aportó la clasificación y trazabilidad de §§2, 13–14 y 33 |
| Frontend & UI/UX (`frontend_uiux`) | `gpt-6.1-sol` · low | Verificó el PNG del logo, Poppins, la paleta y los prompts conceptuales. Propuso recorridos móviles, comparación exacta y alternativas, revisión del carrito, estados, paneles y criterios de accesibilidad. Integrado en §§15, 17 y 25 |
| Backend & Supabase (`backend_supabase`) | `gpt-6.1-sol` · medium | Propuso contratos de cotización, envío y transición, control de concurrencia, idempotencia, autorización de operaciones y coordinación posterior. Revisó la skill y documentación pública. Integrado en §§17–18, 23–24 y 32 |
| Database & PostgreSQL (`database_postgresql`) | `gpt-6.1-sol` · medium | Propuso entidades, cardinalidades, claves de integridad, instantáneas, índices candidatos y alcance RLS. Contrastó las guías locales de Supabase y PostgreSQL. Integrado en §§22–24 |
| DevOps & Deployment (`devops_deployment`) | `gpt-6-luna` · high | Revisó planes publicados, aislamiento de ambientes, CI, migraciones, costos y recuperación de base y Storage. Integrado en §§26–27 y 31 |
| QA & Security (`qa_security`) | `gpt-6.1-sol` · medium | Revisó §§1–21 del borrador y el diseño de permisos informado. Identificó recuperación tras recarga, cobertura de contacto, atención de subpedidos pendientes y pruebas negativas. Integrado en §§17, 29 y 32, y en la matriz |

Documentation, Frontend y Backend iniciaron en paralelo. Database se incorporó al terminar Documentation, y DevOps al terminar Frontend. QA revisó el borrador funcional cuando se liberó una plaza y el flujo ya estaba disponible. La concurrencia se mantuvo dentro del máximo de tres especialistas. El Lead resolvió la integración entre Backend y Database con un solo contrato propuesto de envío y transiciones.

La revisión fue documental. Las pruebas de producto, SQL, infraestructura y seguridad descritas en la especificación quedan para la etapa de desarrollo y validación. Los hallazgos de QA sobre coordinación y gestión de solicitudes abiertas están reflejados como decisiones previas al piloto.

## Ampliación del relevamiento

El Lead reutilizó tres especialistas en paralelo. Frontend revisó los recorridos cliente y comercio, el alta guiada y la dirección manual como alternativa a la ubicación. Database revisó variantes, alias, vigencias y la composición histórica de combos. Backend contrastó la integración oficial de WhatsApp, la confirmación por versión, la notificación separada y su alternativa web. Los tres encargos fueron de solo lectura. El Lead integró el nuevo alcance y verificó la trazabilidad documental. [Relevamiento del cliente y del comercio](DondePido_Relevamiento_Cliente_y_Comercio.md).

## Cierre previo al backend

Backend, Database y QA revisaron la versión 0.3 en solo lectura. Backend propuso identidad, contratos, pedidos y remitente de WhatsApp. Database propuso el esquema conceptual, aislamiento y secuencia de migraciones. QA verificó las brechas de aceptación de cambios, alcance de intentos y avisos, y condiciones de salida. El Lead adoptó cambios versionados de entrega, acceso comercial con MFA y una ruta local con datos ficticios. [Definición de arranque](DondePido_Definicion_Backend_MVP.md).

## Auditoría de consistencia de la versión 0.7

Backend y QA revisaron los cinco documentos en solo lectura. Backend identificó faltantes en publicación inicial, consumo de aprobación, verificación local y criterios por bloque. QA revisó vinculación telefónica, avisos en cola, ocultación e historial. El Lead integró las correcciones en la versión 0.8 y conservó un listado de comprobaciones con datos reales para el piloto. [Definición de arranque](DondePido_Definicion_Backend_MVP.md).
