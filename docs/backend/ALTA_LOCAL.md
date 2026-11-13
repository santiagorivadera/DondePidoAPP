# Registro y alta comercial en local

El backend atiende `POST /api/onboarding`. La solicitud comercial inicial y los datos de referencia son públicos. Supabase Auth administra el registro con correo y contraseña, la confirmación del correo, el inicio de sesión y el MFA. Para las operaciones privadas el backend valida el token en Auth y pasa la identidad verificada a PostgreSQL dentro de una transacción.

## Arranque

Desde la raíz del repositorio y con Docker iniciado:

```powershell
supabase start
supabase migration up --local
npm ci
npm run local:setup
npm run dev
```

`local:setup` crea una identidad de conexión local con permiso para asumir el rol del backend y genera `.env.local`. Si el archivo ya existe, conserva esa configuración. Supabase API escucha en `http://127.0.0.1:55421`, Mailpit en `http://127.0.0.1:55424` y Next.js en `http://127.0.0.1:3000`. El SMS simulado aparece en Mailpit con el identificador del desafío. El código se ingresa en la verificación y no viaja en la respuesta al solicitarlo.

## Operaciones

Enviar JSON con `action`. Las respuestas exitosas usan `data`. `reference` y `application.request` son públicas. Para las demás, enviar `Authorization: Bearer <token de Supabase Auth>`. Las acciones de administración requieren MFA.

| Acción | Datos y efecto |
| --- | --- |
| `reference` | Devuelve ciudades habilitadas y rubros con sus identificadores |
| `application.request` | `email`, `sector` y `observation`. Recibe la solicitud inicial con una respuesta genérica. Después de confirmar ese correo, el titular puede consultar su estado |
| `profile` | `firstName` y `lastName` guardan el perfil de la cuenta con correo confirmado |
| `phone.issue` | `phone` en formato internacional. Devuelve el identificador del desafío |
| `phone.verify` | `phone`, `challengeId` y `code`. Verifica y vincula el número |
| `application.submit` | `sector` y `observation`. Toma el correo confirmado de la cuenta |
| `application.mine` | Lista las solicitudes del correo de la sesión |
| `application.inbox` | Lista solicitudes para administración |
| `application.decide` | `applicationId`, `decision`, `reason` y `cityId` al aprobar. Las decisiones son `approved`, `rejected` o `revoked` |
| `logo.upload` | `mimeType` y `base64`. Devuelve la referencia privada del logo PNG, JPEG o WebP, de hasta 256 KiB |
| `application.complete` | `applicationId`, `name`, `address` y la referencia `logo`. Crea la ficha y su membresía una sola vez |
| `business.mine` | Lista las fichas de las membresías activas de la cuenta |
| `business.hours` | `businessId` y `hours` con días ISO de 1 a 7 y tramos `[inicio, fin]` en minutos del día. Un fin menor al inicio indica que el tramo termina al día siguiente |
| `business.publish` | `businessId`, `pickup`, `delivery` y `confirmPublicContact: true`. Publica la ficha con el número verificado del titular como contacto comercial, previa autorización explícita |
| `business.controls` | `businessId`, `expectedVersion`, `hidden`, `relevance` o ambos y `note` opcional. Ajusta visibilidad y relevancia con autorización administrativa |

La carga del logo usa un bucket privado con acceso por cuenta. La ficha comienza en borrador. [Supabase Auth](https://supabase.com/docs/guides/auth/passwords) · [Supabase MFA](https://supabase.com/docs/guides/auth/auth-mfa).

## Probar las pantallas

- Desde `/` entrá a Kioscos o Gastronomía. En `/explorar` buscá ofertas y abrí la ficha de un comercio. En `/carrito` elegí retiro o entrega por comercio. Consultá las solicitudes enviadas en `/pedidos`.
- En `/cuenta` podés ingresar, registrarte, recuperar la contraseña, verificar el teléfono y configurar el segundo factor.
- En `/gestion` podés solicitar un alta. Al ingresar con un comercio aprobado, accedés a la ficha, catálogo, pedidos e indicadores. En `/gestion/administracion` se gestionan solicitudes, visibilidad, destacados y referencias.

Para publicar un producto individual de kiosco, elegí una presentación del catálogo administrado. La oferta hereda su nombre, categoría y marca. Gastronomía admite productos propios. Los combos y las rebajas usan la disponibilidad manual de cada comercio. El panel de pedidos muestra eventos históricos y los picos de pedidos completados en la zona horaria de la ciudad.

Para habilitar administración en local, primero registrá y confirmá el correo de la cuenta. Ejecutá `npm run local:admin -- correo@ejemplo.test` y completá la configuración de MFA desde la cuenta.

## Promociones destacadas en portada

En `/gestion`, Administración puede subir la imagen que entrega el comercio, escribir el título, ordenar el carrusel y definir una fecha de inicio o fin. Cada imagen enlaza al catálogo del comercio. La portada omite la sección cuando no hay publicaciones vigentes. Ocultar el comercio retira sus destacados. Para retirar una promoción individual, desactivala desde su ficha.

Para el piloto, la carga y la selección quedan a cargo de Administración. Como opción comercial posterior, ofrecer espacios por períodos definidos, identificarlos como «Patrocinado» y medir impresiones y clics para el reporte del comercio. La relevancia del listado general se gestiona por separado. Precio, cupos y duración comercial quedan pendientes de validar.

## Verificación

Con Supabase y Next.js locales activos:

```powershell
supabase test db --local
supabase db lint --local --fail-on error
npm run test:onboarding
npm run test:market
npm run test:featured
npm run typecheck
npm run build
```

Las pruebas integrales crean cuentas, comercios y ofertas ficticias en el entorno local. Mailpit recibe el correo de confirmación y los códigos SMS simulados. `npm run test:market` también despacha un aviso simulado y verifica su contenido en Mailpit.

La prueba de navegador móvil usa Chrome a 390 px, un kiosco y una rotisería ficticios de Deán Funes. Con Playwright instalado en `tooling`, ejecutá `npm run test:market -- --mobile-fixtures` y después `node tests/mobile-demo.local.mjs`. La prueba verifica retiro y entrega en el mismo carrito, confirmación y rechazo desde el panel, estados en el historial y contenido del aviso en Mailpit. Eliminá `.playwright-cli/demo-fixtures.json` después de la prueba. El archivo contiene sesiones locales de cuentas ficticias y está excluido de Git.

La confirmación elegible registra un aviso en cola con consentimiento del cliente. Para probarlo manualmente con datos ficticios, ejecutá `npm run local:dispatch-notices -- --order UUID` y buscá «DondePido WhatsApp local» en Mailpit. El simulador vuelve a comprobar el consentimiento, el destinatario y el estado antes del despacho. Un resultado incierto requiere revisión antes de un reenvío.

La integración opcional de SMS está preparada para Twilio. Para habilitarla en validación se configura `DONDEP_SMS_PROVIDER=twilio` y se cargan del lado servidor `DONDEP_TWILIO_ACCOUNT_SID`, `DONDEP_TWILIO_API_KEY_SID`, `DONDEP_TWILIO_API_KEY_SECRET` y `DONDEP_TWILIO_SMS_SERVICE_SID`. La opción está prevista para celulares argentinos. La recepción real y la cobertura del remitente quedan por verificar con el proveedor. [Documentación de Twilio](https://www.twilio.com/docs/messaging/api/message-resource).

Para una prueba real desde un pedido ficticio, cargá las credenciales Twilio en el entorno local y configurá `DONDEP_TWILIO_WHATSAPP_FROM` y `DONDEP_TWILIO_WHATSAPP_TEST_TO` con los números en formato internacional. Confirmá el pedido con la cuenta de prueba que vinculó ese celular y autorizó WhatsApp. Ejecutá `node --env-file=.env.local scripts/dispatch-notices-local.mjs --order UUID --twilio sandbox` durante la ventana abierta por el mensaje del celular al Sandbox. Usá un pedido que siga en cola.

Para verificar una plantilla aprobada, usá `--twilio template` con un remitente habilitado y configurá también `DONDEP_TWILIO_WHATSAPP_SERVICE_SID` y `DONDEP_TWILIO_WHATSAPP_CONTENT_SID`. El texto propuesto es «Tu pedido {{1}} en {{2}} está confirmado. Productos {{3}}. {{4}}. Para coordinar con el comercio, usá este contacto. {{5}}. Gracias por usar DondePido». El comando imprime el identificador del mensaje aceptado. Verificá la entrega en Messaging Logs. [Plantillas de WhatsApp en Twilio](https://www.twilio.com/docs/whatsapp/tutorial/send-whatsapp-notification-messages-templates).

Para el piloto quedan el despacho programado en validación, la confirmación de entrega, la aprobación de la plantilla y la clasificación explícita de productos restringidos. El historial y la bandeja cargan hasta 100 pedidos. Quedan pendientes la paginación, la jerarquía de categorías y el formulario de sugerencias de productos o marcas faltantes. La administración puede dar de alta presentaciones directamente.
