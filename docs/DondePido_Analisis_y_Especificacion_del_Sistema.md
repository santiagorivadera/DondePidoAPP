# DondePido. — Análisis y especificación del sistema

**11 de noviembre de 2026 · Versión 0.9 · Base de trabajo para el prototipo funcional**

Los recorridos completos, la carga comercial, las promociones y la confirmación se detallan en el [relevamiento funcional del cliente y del comercio](DondePido_Relevamiento_Cliente_y_Comercio.md).

Los criterios específicos para desarrollar localmente, los contratos y los datos necesarios para habilitar el piloto se fijan en la [definición de arranque del backend](DondePido_Definicion_Backend_MVP.md). Ese documento concreta las propuestas de esta especificación.

**Confirmado** identifica decisiones de la solicitud y del proyecto. **Propuesta** identifica el diseño recomendado para revisión. **Pendiente** identifica una decisión abierta, con recomendación y dependencias en §33. Los objetivos de servicio, contratos, pantallas y entidades son propuestas. La matriz inventaría los RF y RNF, y el informe registra la revisión de especialistas. [Matriz de requerimientos](DondePido_Matriz_de_Requerimientos.md) · [Informe de coordinación](DondePido_Informe_de_Coordinacion.md).

## 1. Resumen ejecutivo

DondePido reúne ofertas locales en Deán Funes, Córdoba, Argentina, en dos entradas principales, Gastronomía y Kioscos. El cliente descubre productos y promociones, compara y envía solicitudes de retiro o envío desde un carrito común. El registro vincula el teléfono mediante un código SMS. Cada comercio administra su surtido y confirma o rechaza su subpedido. La confirmación dispara un aviso por WhatsApp para pedidos elegibles. Primero se completa el prototipo con comercios ficticios y después se presenta la propuesta para incorporar comercios reales. [Municipalidad de Deán Funes](https://www.deanfunes.gob.ar/contacto.html).

## 2. Introducción y antecedentes

- La solicitud funcional del 11/11/2026 define el producto y los límites comerciales. [Instrucciones del equipo](../AGENTS.md).
- La carpeta de trabajo contiene configuración del equipo y herramientas. En la inspección inicial no se detectó código de aplicación, esquema, API ni metadatos Git en la raíz. El inventario describe herramientas locales y el plugin, sin proyecto Supabase elegido para DondePido. [Configuración del equipo](multiagent/README.md) · [Inventario de herramientas](tooling/README.md).
- Se verificaron la referencia de marca, el PNG transparente, la paleta, los archivos Poppins y las tres interfaces conceptuales del kit externo `C:/Users/Santiago/Desktop/DondePido-kit`. Las maquetas aportan antecedentes de interfaz y contienen datos ilustrativos. La documentación disponible no aporta entrevistas, métricas de uso ni observaciones directas del proceso comercial.

## 3. Descripción del problema

La información necesaria para decidir una compra local puede estar repartida entre distintos canales y mostrarse con presentaciones, precios y vigencias difíciles de cotejar. La hipótesis a validar en el piloto es que una consulta unificada reduce el esfuerzo de búsqueda y facilita que un pedido llegue al comercio correcto. El beneficio depende de que los comercios mantengan su oferta actualizada y respondan las solicitudes.

## 4. Justificación de la solución

Un catálogo con ofertas por comercio permite comparar precios de la misma presentación y explorar alternativas de un rubro. El carrito común reduce pasos para el cliente. El subpedido conserva la autonomía comercial y acota la información visible a cada destinatario. La operación directa de pagos y entregas mantiene el piloto centrado en descubrimiento, solicitud y coordinación.

## 5. Objetivo general del proyecto

Facilitar la elección y el pedido de productos de comercios locales mediante una plataforma web común, validando si el flujo aporta valor a clientes y comercios.

## 6. Objetivos específicos

1. Hacer localizables productos, promociones y comercios por búsqueda y categorías.
2. Mostrar precios y condiciones que permitan distinguir presentaciones equivalentes de alternativas similares.
3. Enviar solicitudes agrupadas por comercio y mostrar su evolución individual.
4. Permitir al comercio operar catálogo y pedidos con permisos acotados.
5. Medir adopción y respuesta operativa durante el piloto mediante eventos del sistema.

## 7. Objetivo del sistema

Publicar la oferta vigente declarada por comercios y transformar un carrito validado en un registro agrupador para el cliente y un subpedido por comercio, con importes históricos, estado trazable y acceso por rol. Un envío exitoso significa que la solicitud quedó registrada y visible en la bandeja correspondiente.

## 8. Alcance y límites

| Confirmado | Propuesta para el piloto |
| --- | --- |
| Búsqueda de productos y comercios, categorías, comparación, promociones y fichas en Deán Funes | Navegación pública con modelo preparado para más localidades y rubros |
| Dos accesos principales, Gastronomía y Kioscos | Gastronomía reúne rotiserías, restaurantes y bares. Kioscos reúne kioscos y despensas. Los rubros organizan comercios y reutilizan las categorías de productos |
| Administración ajusta la relevancia de cada comercio de 1 a 100 o lo oculta por completo en un clic | Rotación proporcional en el listado de su ciudad y rubro. Igual exposición esperada con valores iguales. Ocultación reversible |
| Registro de cliente y registro comercial por separado. Correo, contraseña, nombre, apellido y teléfono único verificado por SMS | Una identidad puede comprar y administrar sus comercios autorizados. El alta comercial requiere aprobación previa del correo indicado |
| Carrito único, distribución automática y gestión y confirmación por cada comercio | Cuenta al enviar, catálogo base moderado, disponibilidad manual y bandeja persistente |
| Retiro o envío por comercio, dirección y ubicación opcional para entrega | Selección por subpedido. El comercio informa cobertura, costo externo y plazo, y el cliente revisa la dirección antes de compartirla |
| Aviso automático de pedido confirmado por WhatsApp desde el primer día | El comercio confirma. El aviso identifica comercio, pedido, dirección correspondiente y productos o combo, y ofrece un canal para coordinar |
| Carga por categorías, combos, rebajas, historial y estadísticas del comercio | Catálogo común moderado, gestión de ofertas por comercio y tableros por mes, día y horario |
| Pago, retiro y entrega coordinados por comercio y cliente | Mostrar el total de productos y aclarar que las condiciones y cargos externos se acuerdan con cada comercio |

Quedan fuera del MVP las comisiones por venta, la pasarela y el procesamiento de pagos, el delivery propio y las aplicaciones móviles empaquetadas. Se confirma que ningún pedido descuenta ni reserva stock. Se propone posponer integraciones de punto de venta, mensajería propia, promociones adicionales a combos y rebajas, seguimiento de ubicación y soporte multiciudad en operación.

## 9. Descripción del modelo de negocio

DondePido conecta demanda local con comercios. Aporta descubrimiento, visibilidad y recepción organizada de solicitudes. Cada comercio es responsable de mantener su oferta y acordar las condiciones de cumplimiento con sus clientes. La etapa piloto puede medir repetición, cobertura del catálogo, tiempos de respuesta y costo operativo. Monetización, planes comerciales, acuerdos y responsables del soporte quedan pendientes. Los importes de productos registrados son valores de solicitudes, sin evidencia de cobro.

El carrusel de portada permite mostrar imágenes de promociones aportadas por los comercios. En el piloto, Administración selecciona y programa los destacados. Como opción comercial posterior, DondePido puede ofrecer espacios patrocinados por período y reportar impresiones y clics. Quedan por validar precio, cupos y duración.

## 10. Identificación de actores y roles

| Actor | Responsabilidad y acceso propuestos |
| --- | --- |
| Visitante | Consulta información publicada y prepara un carrito sin datos personales |
| Cliente registrado | Con correo confirmado y teléfono vinculado, envía solicitudes, ve sus pedidos y accede al contacto del comercio correspondiente |
| Operador de comercio | Actúa solo en comercios con membresía activa. Gestiona ficha, ofertas, disponibilidad, promociones y subpedidos asignados |
| Administración de DondePido | Aprueba o rechaza solicitudes por correo y gestiona membresías, taxonomía y moderación. El soporte de pedidos requiere permiso explícito, motivo y auditoría |
| Sistema | Valida publicación, precios y permisos, agrupa y registra pedidos y cambios de estado |

Una identidad puede operar en varios comercios mediante membresías separadas. La gestión de personal por el propio comercio y la granularidad de roles están pendientes.

## 11. Relevamiento de procesos

| Proceso | Entrada y resultado esperado | Aspecto a relevar en piloto |
| --- | --- | --- |
| Alta y catálogo | Solicitud con correo, rubro y observación. La aprobación habilita el registro para el correo verificado. El comerciante completa datos del local, horarios y logo | Tiempo de revisión, validación de la ficha y gestión de altas del catálogo |
| Descubrimiento | Consulta o categoría en una ciudad. Ofertas comparables o alternativas con contexto | Cómo buscan clientes y qué atributos necesitan según rubro |
| Envío y recepción | Carrito revisado. Pedido agrupador y bandejas por comercio | Horarios, cobertura del canal y tiempo razonable de respuesta |
| Confirmación y coordinación | Subpedido recibido. Decisión comercial y coordinación directa | Motivos de rechazo, cambio, cancelación y falta de respuesta |
| Soporte y control | Incidencia o dato incorrecto. Intervención registrada | Responsables, acceso mínimo y política de conservación |

## 12. Proceso de negocio actual y propuesto

**Actual, hipótesis de relevamiento.** El cliente busca en canales de comercios y consulta condiciones individualmente. El comercio recibe pedidos por sus propios medios. Se debe verificar con comercios piloto cómo publican precios y reciben, responden y completan pedidos.

**Propuesto.** Operación habilita comercios y mantiene el catálogo común. El comercio publica ofertas, combos y rebajas. El cliente compara, elige retiro o envío por comercio y envía el carrito. El sistema crea los subpedidos en una transacción. El comercio confirma las condiciones acordadas o rechaza. DondePido registra la decisión, envía el aviso automático al confirmar cuando corresponde y permite coordinar el cumplimiento.

## 13. Requerimientos funcionales numerados y priorizados

La matriz define **RF-01 a RF-35** con prioridad, origen, dependencia y aceptación. RF-29–32 cubren registro, teléfono único, solicitud comercial y alta restringida. RF-33 y RF-34 cubren relevancia y ocultación administrativa. RF-35 cubre los destacados en portada.

## 14. Requerimientos no funcionales medibles

La matriz define **RNF-01 a RNF-10** con objetivos propuestos y métodos de prueba. El escenario de referencia de carga es sintético y debe ratificarse antes de usarlo como criterio de lanzamiento. Disponibilidad técnica y tiempo de respuesta del comercio se miden por separado.

## 15. Casos de uso e historias de usuario

| Caso e historia | Flujo principal | Variante y evidencia |
| --- | --- | --- |
| CU-01 · Como visitante quiero comparar la Coca-Cola de una presentación exacta | Busco, selecciono presentación y veo ofertas de mi ciudad | Presentaciones distintas quedan en grupos separados. Los lomitos de distintos comercios aparecen como alternativas descritas. RF-01, RF-03, RF-04 |
| CU-02 · Como cliente quiero enviar un carrito a dos comercios | Agrego productos, ingreso, reviso subtotales y envío | Un cambio de precio exige revisión. Un reintento ante respuesta perdida devuelve el mismo grupo. RF-07–10 |
| CU-03 · Como comerciante quiero responder mis solicitudes | Abro la bandeja, consulto el detalle y acepto o rechazo | Una decisión simultánea con versión vieja devuelve conflicto. El otro comercio conserva su estado. RF-11, RF-14, RF-15 |
| CU-04 · Como cliente quiero coordinar el retiro o la entrega | Elijo modalidad, ingreso dirección si corresponde y recibo el aviso cuando confirma el comercio | El aviso contiene dirección e ítems y permite coordinar. Si no concedo ubicación, completo la dirección manualmente. RF-12, RF-13, RF-23–26 |
| CU-05 · Como operador quiero publicar una oferta y pausar su disponibilidad | Cargo precio y presentación, activo promoción válida y actualizo disponibilidad | Una pausa deja de ofrecer el producto y el historial conserva los datos originales. RF-16, RF-17 |
| CU-06 · Como administrador quiero habilitar un comercio | Verifico ficha, ciudad, contacto y responsable, y asigno acceso | La revocación surte efecto en la siguiente operación protegida. Se registra la acción. RF-18, RNF-01, RNF-06 |

## 16. Reglas de negocio

| ID | Regla |
| --- | --- |
| RN-01 | La comparación exacta requiere variante y presentación equivalentes, con marca y unidad cuando corresponda. Una oferta sin vínculo verificado puede verse como alternativa con su descripción. Propuesta |
| RN-02 | El carrito pertenece a una ciudad y usa una sola moneda. En Deán Funes se usa ARS. Los subtotales se calculan por comercio con aritmética exacta |
| RN-03 | El pedido no reserva ni descuenta stock. Como propuesta, el comercio administra disponibilidad manual y el servidor la revalida al enviar |
| RN-04 | Combos y rebajas por porcentaje o precio final, con vigencia. Se propone una rebaja efectiva por oferta y precio propio para cada combo, sin reaplicar rebajas individuales. La hora autoritativa es la del servidor |
| RN-05 | El envío crea un subpedido por comercio en una sola transacción. Una diferencia relevante bloquea el envío de todo el carrito y requiere revisión. Propuesta |
| RN-06 | La edición de catálogo afecta cotizaciones futuras. El subpedido conserva la presentación, cantidades, precios y descuentos aceptados al enviarlo. Propuesta |
| RN-07 | Cada comercio decide sobre su subpedido. Un rechazo posterior deja intactos los subpedidos restantes. Propuesta |
| RN-08 | Mostrar subtotal de productos y cargo de envío por separado. Mostrar el importe combinado cuando se conoce el cargo. Si queda a acordar, obtener aceptación antes de confirmar. El pago y el cumplimiento se coordinan con cada comercio |
| RN-09 | Un comercio oculto desaparece de todas las superficies públicas y queda bloqueado para nuevos envíos. Los pedidos ya registrados y el historial quedan accesibles para sus participantes |

## 17. Flujo del carrito multicomercio

1. El cliente selecciona ofertas y cantidades. El carrito identifica cada comercio, subtotal y total de productos. Propuesta inicial de borrador en el dispositivo, sin contacto personal y con retorno al carrito tras el acceso.
2. El servidor cotiza con oferta, disponibilidad, promoción efectiva, ciudad, moneda y revisión de lo aceptado. Si el cliente cambia de ciudad, debe resolver el carrito anterior antes de mezclar selecciones.
3. El cliente elige retiro o envío por comercio. Para envío revisa dirección y ubicación si la agregó. Con sesión válida, se propone persistir en servidor un intento privado e inmutable de corta duración con la selección, revisión y datos de entrega. La clave de idempotencia se vincula al cliente y al contenido de ese intento. El dispositivo conserva solo una referencia opaca para recuperar el intento con la misma identidad tras una recarga. El servidor conserva acceso al resultado confirmado según la política de idempotencia.
4. Dentro de una transacción, se resuelve primero un reintento ya confirmado. Para un envío nuevo se revalidan las condiciones y se crean grupo, subpedidos, renglones y eventos iniciales. La bandeja consulta los subpedidos persistidos. Un fallo en una inserción revierte el conjunto.
5. Una diferencia de precio, vigencia o disponibilidad devuelve las líneas afectadas y mantiene el carrito. El cliente actualiza o retira las líneas y acepta una nueva revisión con un nuevo intento. Una clave repetida con datos distintos devuelve conflicto.
6. Ante pérdida de respuesta se indica que el resultado está pendiente de comprobar. Para ese intento solo se permite reintentar con la misma clave y el mismo contenido hasta resolverlo. Al recuperar el resultado, se muestra el grupo y se limpia el carrito correspondiente. Después, las respuestas comerciales evolucionan de forma independiente.

## 18. Gestión y estados de pedidos y subpedidos

| Estado de origen | Acción y actor | Estado resultante |
| --- | --- | --- |
| Creación transaccional | Cliente envía el carrito validado | Recibido |
| Recibido | Operador habilitado confirma disponibilidad y condiciones acordadas | Confirmado, con aviso automático por WhatsApp si es elegible |
| Recibido | Operador habilitado rechaza y registra un motivo | Rechazado |
| Confirmado | Operador registra retiro o entrega realizados | Completado |
| Recibido | Cliente titular cancela o vence el plazo configurado | Cancelado o Vencido, respectivamente |
| Confirmado | Operador autorizado cancela con motivo antes de completar | Cancelado |

La confirmación corresponde al comercio. Los cambios de modalidad, cargo de envío, dirección o franja comprometida se proponen en una revisión y el cliente la acepta antes de confirmar. Para cambiar productos, cantidades o su precio, el comercio rechaza con motivo y el cliente puede volver a pedir. Rechazado, Completado, Cancelado y Vencido son terminales. La bandeja distingue estado de pedido y estado de notificación. Las transiciones verifican versión y permiso, y registran su evento. El grupo muestra un resumen derivado de los subpedidos. [Estados y contratos del backend](DondePido_Definicion_Backend_MVP.md).

## 19. Funcionalidades del panel de comerciantes

- Bandeja paginada por estado y antigüedad, con contador de recibidos y actualización visible. Detalle con líneas, subtotal, datos mínimos de coordinación y acciones habilitadas.
- Edición de ficha comercial, horarios informativos, canal de contacto, precios y disponibilidad. Asociación a variantes ya verificadas o solicitud de revisión por operación.
- Combos con precio propio y rebajas por porcentaje o precio final, vigencia y vista previa. Configuración de modalidades, confirmación y cierre por subpedido, historial e indicadores del propio comercio.

## 20. Funcionalidades del panel administrativo

El panel lista solicitudes de comercios y permite aprobar o rechazar por correo y rubro con auditoría. Aprobar habilita el registro solo al titular del correo verificado. También permite gestionar publicación, suspensión, membresías y catálogo. La moderación resuelve altas y correcciones de productos preservando el historial. El soporte de pedidos requiere un permiso específico y motivo de consulta.

Cada comercio tiene un control de relevancia de 1 a 100 y acciones «Ocultar» o «Mostrar de nuevo». La relevancia ajusta la frecuencia de aparición en la primera posición del listado general. Todos parten con el mismo valor y tienen la misma exposición esperada. Ocultar retira ficha, productos, promociones e imágenes de la vista pública. Se puede anotar un motivo interno, como un pago pendiente. [Reglas de relevancia y visibilidad](DondePido_Definicion_Backend_MVP.md).

Administración puede cargar una imagen y un título, elegir un comercio, ordenar los destacados y programar su vigencia. El carrusel solo muestra destacados habilitados y vigentes de comercios visibles. El cliente abre el catálogo del comercio desde la imagen destacada.

## 21. Sistema de estadísticas e indicadores

Los agregados usan la fecha del evento que mide cada indicador y la zona horaria del comercio. La interfaz identifica fecha y hora de corte. El comercio accede a sus datos y Operación a agregados autorizados.

| Indicador | Definición |
| --- | --- |
| Solicitudes y subpedidos | Conteos separados de grupos enviados y subpedidos recibidos. Una repetición idempotente cuenta una vez |
| Decisiones y tasa de aprobación | Aprobados ÷ subpedidos decididos, agrupados por fecha de decisión. Mostrar rechazados y pendientes por separado. Sin datos si el denominador es cero |
| Tiempo a primera respuesta | Mediana y p90 del tiempo de recibido a aprobado o rechazado entre los que respondieron, con tamaño de muestra y pendientes visibles |
| Comercios y ofertas activas | Comercios publicados y ofertas publicadas y disponibles al corte, por ciudad y rubro |
| Valor de productos solicitados | Suma de importes de líneas del grupo de subpedidos elegido, identificando moneda, cohorte y filtro de estado |
| Actividad por mes, día y franja | Volumen recibido por fecha de solicitud y volumen completado por fecha de entrega o retiro, en la zona horaria del comercio. El importe completado registra valor de productos y no acredita cobro |

Para el piloto se propone una revisión semanal de catálogo, aceptación, respuesta y costo operativo. La instrumentación de búsquedas, conversiones y repetición se valida antes de recolectar eventos adicionales. El valor de productos solicitados mide intención registrada.

## 22. Propuesta de estructura de datos

Los nombres son conceptuales. El diseño detallado y sus migraciones se deciden en desarrollo.

| Entidad | Relaciones e invariantes |
| --- | --- |
| Ciudad | Identidad estable, zona horaria y estado de habilitación. Una ciudad reúne varios comercios operativos |
| Comercio operativo | Pertenece a una ciudad. Contiene identidad pública, rubro de navegación, tipo de comercio, horarios, estado y canal comercial autorizado. Se propone un rubro principal entre Gastronomía y Kioscos. Si hay sucursales, queda pendiente decidir cuál recibe el pedido |
| Identidad y perfil | Identidad de Supabase Auth con correo verificado y contraseña. Perfil con nombre y apellido y vinculación privada de teléfono, única por número y por cuenta activa |
| Solicitud comercial | Correo normalizado, rubro, observación, estado y auditoría de la decisión. La autorización aprobada es de un solo uso y se verifica contra el correo confirmado |
| Horario y logo | Tramos por día y excepciones por fecha, con zona horaria del comercio. Imagen del logo o marca asociada a la ficha |
| Membresía | Vincula identidad y comercio con permiso y vigencia. Una membresía por par, revocable. Roles de plataforma separados |
| Categoría, marca, producto de referencia, variante y alias | Catálogo común administrado. La variante normaliza presentación y soporta comparación exacta. La marca puede omitirse para platos propios. Los alias ayudan a encontrar resultados y sugerir coincidencias |
| Oferta | Pertenece a un comercio y opcionalmente a una variante verificada. Registra presentación publicada, categoría, precio, moneda, disponibilidad y revisión. Un plato sin variante puede aparecer como alternativa |
| Rebaja y combo | Rebaja ligada a una oferta con precio final o porcentaje y fin opcional. Combo vendible con título, composición, precio y vigencia propios. Los componentes pertenecen al mismo comercio |
| Pedido agrupador | Pertenece a un cliente y a una ciudad. Contiene fecha y moneda. Tiene uno o más subpedidos |
| Subpedido | Único por grupo y comercio, con subtotal, modalidad, estado y versión. Dirección y coordenadas privadas solo para envío. Conserva la versión de las condiciones confirmadas y el vínculo aunque se suspenda el comercio |
| Renglón | Pertenece a un subpedido. Referencia una oferta de ese comercio y guarda su instantánea comercial, cantidad positiva e importe exacto |
| Evento | Pertenece a un subpedido. Guarda actor, fecha, versión, transición y motivo permitido. La auditoría administrativa se conserva por separado |
| Registro de idempotencia | Clave única por cliente para el envío, huella del comando y referencia al resultado. Se escribe en la misma transacción que el grupo |
| Intento privado y aviso | Intento autenticado con plazo de conservación, y tarea de notificación única por subpedido, versión y tipo. El aviso registra estado y referencia del proveedor por separado |

Vínculos que deben verificarse en la base: coherencia ciudad–grupo–comercio, comercio–subpedido–oferta, moneda del grupo y unicidad de subpedido. Preservar historia al retirar ofertas mediante desactivación o una política de archivado compatible con las referencias. Representar importes en unidades menores enteras con moneda explícita y límites, y calcular subtotales en servidor. Indexar según las consultas de membresía por usuario y comercio, bandeja por comercio y estado, historial por cliente y catálogo publicado por ciudad, categoría o variante. Validar planes con datos sintéticos representativos.

## 23. Arquitectura tecnológica

Stack previsto confirmado en la solicitud. React y TypeScript con Next.js App Router y Tailwind para la web. Supabase Auth para identidad, PostgreSQL para datos y transacciones, RLS para aislamiento y Storage para imágenes. GitHub para versionado y Vercel para hosting. La separación propuesta comprende presentación, casos de uso, acceso a datos y configuración. Usar funciones de servidor de Next.js cuando corresponda y considerar Edge Functions ante una necesidad concreta.

| Operación lógica propuesta | Entrada | Resultado y controles |
| --- | --- | --- |
| Consultar catálogo | Ciudad, texto, filtros y paginación | Proyección pública de fichas y ofertas vigentes |
| Preparar intento | Ciudad, ofertas y cantidades, modalidad por comercio y dirección si corresponde | Intento privado, precios y subtotales, revisión y vigencia |
| Enviar intento | Referencia del intento, revisión y clave de idempotencia | Grupo y subpedidos, resultado previo, diferencias sin escritura de pedidos o error tipado |
| Cambiar estado | Subpedido, acción, versión esperada y motivo o condiciones si aplica | Estado y evento en la misma transacción, o rechazo por versión, transición o permiso. Al confirmar se registra también la tarea de aviso para pedidos elegibles |

El navegador aporta selecciones y cantidades. El servidor deriva identidad y calcula importes. Para confirmar, la propuesta es adquirir bloqueos de comercio y oferta en orden estable y hacer participar a las escrituras de publicación, disponibilidad y promoción del mismo protocolo. Esto incluye altas de promociones y suspensiones. Evaluar vigencia con un instante común de servidor tras obtener los bloqueos. Resolver transacciones competidoras y conflictos de idempotencia sin mostrar pedidos incompletos. La firma, mecanismo de invocación y grants exactos quedan para un ADR y pruebas de integración. [Aislamiento transaccional de PostgreSQL](https://www.postgresql.org/docs/current/transaction-iso.html).

Conservar el mismo intento durante reenvíos y evitar que un doble toque cree otro intento. El servidor consume el intento una sola vez aunque lleguen claves distintas para esa misma referencia. Los borradores independientes de distintos dispositivos pueden crear envíos distintos. La recuperación se vincula a la identidad que creó el intento y al resultado persistido.

## 24. Seguridad, autenticación y autorizaciones

Verificar la sesión Supabase Auth en servidor para acciones protegidas. El acceso usa correo confirmado y contraseña. Validar teléfono vinculado para completar el alta personal, aprobación vigente para el alta comercial y membresía activa con MFA para funciones comerciales protegidas. Las páginas y respuestas privadas quedan fuera de cachés compartidas. Los roles se validan en servidor y base de datos. [Supabase Auth SSR](https://supabase.com/docs/guides/auth/server-side/creating-a-client?queryGroups=framework&framework=nextjs) · [Auth con contraseña](https://supabase.com/docs/guides/auth/passwords).

| Recurso | Lectura autorizada | Escritura autorizada |
| --- | --- | --- |
| Catálogo | Proyección publicada para el público. Borradores solo del comercio correspondiente y moderación autorizada | Operador con membresía activa dentro de su alcance. Administración explícita para datos de referencia y moderación |
| Grupo | Cliente propietario | Operación transaccional autorizada |
| Subpedido, renglones y eventos | Cliente propietario y operador activo del comercio destinatario. Soporte excepcional con permiso específico y auditoría | Operaciones transaccionales autorizadas. El comercio solo cambia el estado de sus subpedidos mediante transiciones permitidas |
| Contacto privado | Titular y destinatario autorizado según finalidad y política aprobada | Titular u operación autorizada según el dato |
| Membresías y roles | Alcance mínimo para la operación propia y administración autorizada | Administración habilitada. Las modificaciones quedan auditadas |
| Imágenes | La entrega pública verifica la visibilidad de la ficha y el contenido. Los archivos originales tienen acceso privado | Operador habilitado para su comercio y moderación autorizada |

Aplicar grants explícitos y RLS por recurso, con reglas de lectura y escritura y pruebas de referencias cruzadas. Restringir DML directo del navegador sobre pedidos, líneas y eventos. Verificar exposición de tablas, vistas y funciones, y permisos de ejecución. Diseñar un acceso acotado a las operaciones privilegiadas con identidad verificada, privilegios mínimos y auditoría. Las claves privilegiadas se mantienen en servidor. [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security) · [Seguridad de la Data API](https://supabase.com/docs/guides/api/securing-your-api).

En Storage, separar publicación y borradores, comprobar pertenencia del objeto y de la oferta, y validar formato, tamaño y contenido de imágenes. Mantener datos personales fuera de objetos públicos, URL y registros operativos. Para WhatsApp, verificar autorización y número, informar que el aviso incluirá la dirección de entrega y usar el domicilio confirmado solo para el destinatario verificado. Excluir coordenadas y referencias sensibles. Autenticar eventos del proveedor y deduplicar sus actualizaciones. Definir acceso, conservación y borrado antes del piloto. [Control de acceso a Storage](https://supabase.com/docs/guides/storage/security/access-control).

## 25. Diseño UI/UX y pantallas necesarias

Usar el logo aprobado del kit, Poppins y la paleta petróleo `#0F4D4E`, naranja `#FF7A3D`, turquesa `#5ECBC6`, marfil `#FAF7F3` y grafito `#1F2937`. Verificar contraste según cada combinación y tamaño de texto. Referencias locales `Referencia-aprobada.png`, `PNG-transparentes/DondePido-logo-transparente.png`, `Paleta.json` y `Tipografia/`.

| Área | Pantallas y contenido |
| --- | --- |
| Descubrimiento | Inicio con dos accesos principales, Gastronomía y Kioscos. Resultados, categorías y promociones por rubro, comparación de presentaciones exactas, alternativas con porción o descripción y ficha comercial |
| Cliente | Registro personal, confirmación de correo, vinculación de teléfono, acceso con retorno al carrito, historial y detalle por comercio |
| Comercio | Solicitud inicial, registro comercial habilitado por aprobación, ficha con dirección, días y horarios y logo, bandeja, catálogo, promociones e indicadores |
| Operación | Bandeja de solicitudes con observación, rubro y decisión por correo, moderación, membresías, taxonomía y soporte con permisos específicos |

Componentes previstos: filtros, tarjetas de oferta, resumen de importes, control de cantidad, etiquetas de estado y confirmación de acciones. En móvil, priorizar lectura por bloques y acciones alcanzables con teclado y tacto. Diseñar carga, vacío, error recuperable, sesión vencida, acceso denegado, datos cambiados y confirmación. Anunciar cambios de importe y estado a lectores de pantalla y ofrecer foco visible. En el carrito se propone «Enviar solicitudes». En el detalle, el clic a WhatsApp abre voluntariamente un canal externo autorizado y no registra envío de mensaje, aceptación ni cierre. [WCAG 2.2](https://www.w3.org/TR/WCAG22/).

## 26. Infraestructura y despliegue

| Entorno | Uso propuesto y aislamiento |
| --- | --- |
| Local | Desarrollo con datos ficticios y pruebas de migración y permisos. Credenciales locales |
| Validación | Preview o entorno estable autorizado, con proyecto Supabase y credenciales propios. Datos sintéticos y accesos restringidos |
| Producción | Proyecto y variables separados, dominio y TLS, acceso operativo mínimo, respaldos y alertas. Alta y despliegue sujetos a autorización específica |

Al iniciar desarrollo, versionar contratos y migraciones. Configurar CI con lint, tipos, pruebas y build. Validar migraciones y RLS en entorno aislado, revisar compatibilidad entre versión web y esquema y liberar con aprobación aplicable. El rollback de la web y la recuperación de datos tienen procedimientos separados. Ensayar restauración de PostgreSQL y de objetos Storage, que necesitan respaldo separado. Fijar la versión de CLI y revisar su comportamiento y compatibilidad en CI. [Despliegue y branching de Supabase](https://supabase.com/docs/guides/deployment/branching) · [Respaldos](https://supabase.com/docs/guides/platform/backups) · [Historial de cambios de Supabase](https://supabase.com/changelog.md).

Medir latencia, errores, fallos de confirmación, uso y gasto. Incorporar paginación e imágenes acotadas. Toda respuesta pública revalida la visibilidad vigente, incluso con una página, enlace de imagen o cursor anterior. Si se cachea contenido, el acceso debe pasar por esa comprobación. Los precios promocionales cacheados vencen antes del siguiente cambio de vigencia o ante una edición. Cotizar y enviar consultan condiciones autoritativas. Elegir región con datos del piloto y revisar consumo por entorno.

## 27. Análisis preliminar de costos

Precios públicos de referencia consultados el 11/11/2026, en USD. Las cifras son escenarios de planificación.

| Escenario | Base mensual estimada | Supuesto |
| --- | --- | --- |
| Desarrollo local | USD 0 de hosting del stack | Equipo existente, sin recursos alojados. El trabajo de desarrollo tiene costo propio |
| Piloto comercial | Desde USD 45 | Vercel Pro USD 20 y Supabase Pro USD 25 con una instancia Micro cubierta por el crédito de cómputo. Hobby de Vercel se limita a uso personal no comercial |
| Piloto más validación alojada | Desde USD 55 | Escenario anterior más una segunda instancia Micro de referencia en la misma organización Supabase, sujeta a cómputo, cuotas y modalidad elegida |

Sumar dominio, correo transaccional, puestos adicionales, transferencia, almacenamiento, procesamiento y observabilidad excedentes, copias de objetos, impuestos y tipo de cambio. Presupuestar por separado los SMS de verificación, WhatsApp automático y mapas o conversión de coordenadas si se usan. Incluir el costo operativo de incorporación, moderación y soporte. Antes del piloto, fijar presupuesto y umbrales de aviso y estimar consumo con datos de validación. Supabase Free puede pausar proyectos inactivos. [Precios de Vercel](https://vercel.com/pricing) · [Condiciones de Hobby](https://vercel.com/docs/plans/hobby) · [Precios de Supabase](https://supabase.com/pricing) · [Precios de WhatsApp Business Platform](https://whatsappbusiness.com/products/platform-pricing/).

## 28. Riesgos técnicos y comerciales

| Riesgo | Señal | Tratamiento propuesto |
| --- | --- | --- |
| Catálogo escaso o desactualizado | Búsquedas sin resultados, cambios al cotizar y rechazos | Incorporación asistida, responsable por comercio y revisión de catálogo |
| Comparaciones incorrectas | Reclamos por tamaños, variedades o porciones | Variantes verificadas y alternativas con descripción |
| Comercio sin respuesta o canal inaccesible | Subpedidos antiguos y coordinación fallida | Definir cobertura, seguimiento, mensaje al cliente y canal alternativo antes del piloto |
| Duplicados o envíos inconsistentes | Dos grupos de un intento o subpedidos faltantes | Transacción, idempotencia, revalidación y pruebas de carrera |
| Exposición de datos entre cuentas o comercios | Cualquier lectura o escritura fuera de alcance | RLS, grants, proyecciones mínimas, auditoría y pruebas negativas |
| Expectativas incorrectas de entrega o cobro | Consultas sobre cargos, retiro o confirmación | Explicitar total de productos y acuerdos por comercio en carrito y detalle |
| Costo operativo o infraestructura excesivos | Alta manual lenta, consumo superior al presupuesto | Piloto acotado, métricas operativas y límites de gasto |

## 29. Definición del MVP

El núcleo confirmado reúne accesos a Gastronomía y Kioscos, búsqueda, categorías, comparación, combos, rebajas, ficha comercial, carrito único, retiro o envío, gestión, historial e indicadores. El piloto propuesto usa un catálogo común que crece con el surtido de los comercios, disponibilidad manual sin stock, ubicación opcional, creación transaccional, confirmación o rechazo desde la bandeja, aviso automático de confirmación por WhatsApp y cierre por comercio. RF P0 constituyen el mínimo. RNF P0 se verifican antes del piloto.

Para habilitar el piloto se necesita surtido real validado en ambos rubros, comercios operativos, soporte y un flujo completo probado. WhatsApp automático es condición de lanzamiento para subpedidos elegibles. La prueba previa debe comprobar la plantilla aprobada, la entrega al destinatario verificado con dirección e ítems correctos y la coordinación con un operador del comercio. DondePido conserva el estado del pedido si falla el aviso o falta autorización. DP-13 reúne las decisiones de implementación.

Antes de incorporar comercios reales se presenta el prototipo funcional de Deán Funes. Debe pasar el recorrido PA-16 con datos de demostración, incluyendo entrega real de correo, SMS y WhatsApp a números y cuentas autorizados. [Criterios de la demostración](DondePido_Definicion_Backend_MVP.md).

## 30. Funcionalidades para versiones futuras

Evaluar expansión a más ciudades y rubros, sucursales, autoservicio de comercios, permisos granulares, inventario e integraciones, promociones complejas, mensajería y notificaciones, analítica ampliada y aplicaciones Android/iOS mediante Capacitor. Pagos, comisiones y servicios de entrega requerirían una definición de producto propia. Son líneas de evaluación posteriores.

## 31. Roadmap de desarrollo

| Etapa | Dependencia | Resultado y condición de salida |
| --- | --- | --- |
| 0 · Validación de alcance | Especificación revisada | Deán Funes configurada como primera ciudad. Datos ficticios listos para B1. Proveedores y políticas operativas se preparan en paralelo |
| 1 · Base y seguridad | Decisiones de acceso, roles, datos y ambientes | Estructura versionada, contrato de permisos y pruebas base de identidad y aislamiento |
| 2 · Catálogo y descubrimiento | Taxonomía, comparación, promociones y operación acordadas | Alta, moderación, publicación, combos, rebajas y búsqueda probados, incluidos alias y coincidencia por componentes |
| 3 · Carrito y subpedidos | Catálogo y reglas de confirmación, contacto y estados | Envío multicomercio, modalidades, ubicación opcional, confirmación comercial, cierre e indicadores probados. Preparar remitente, elegibilidad y plantillas de WhatsApp en paralelo |
| 4 · Prototipo funcional | Aplicación completa en validación | RF P0 verificados con comercios ficticios, pruebas aplicables de calidad y entrega real de correo, SMS y WhatsApp a destinatarios autorizados. PA-16 |
| 5 · Presentación e incorporación | Prototipo funcional aprobado | Presentar la propuesta y después registrar comercios reales de Deán Funes, con sus horarios, ofertas y canales de atención |
| 6 · Piloto y revisión | Comercios incorporados y salida autorizada | Verificar soporte y recuperación, medir catálogo y respuesta, corregir fricciones y decidir ampliaciones con datos observados |

## 32. Criterios de aceptación y estrategia de pruebas

| ID | Nivel | Evidencia de aceptación |
| --- | --- | --- |
| PA-01 | Integración y extremo a extremo | Dos clientes y dos comercios sintéticos. Un carrito a dos comercios genera un grupo y dos subpedidos, cada uno visible solo al actor que corresponde |
| PA-02 | Integración transaccional | Falla inducida de persistencia o una oferta cambiada produce cero pedidos. El cliente conserva el carrito. Un cambio concurrente de disponibilidad, publicación o promoción produce un resultado coherente con la revisión validada |
| PA-03 | Integración de reintentos | Confirmaciones simultáneas con la misma clave y contenido producen un grupo. Tras respuesta perdida, recarga y cambio posterior de catálogo, el reintento del mismo cliente devuelve el original. Una identidad distinta no puede recuperar el intento. Misma clave con otro contenido para ese cliente devuelve conflicto |
| PA-04 | Integración de estados | Dos acciones competidoras con la misma versión producen una sola transición y evento. El rechazo de un comercio no cambia el otro. Un historial permanece legible después de despublicar una oferta |
| PA-05 | Autorización | Verificar operaciones permitidas y denegadas en interfaz, servidor, base, vistas, acciones administrativas y Storage. Probar identidades y referencias cruzadas, sesión vencida, revocación con sesión vigente, administración sin permiso de soporte, URL privada y acceso directo a datos |
| PA-06 | Interfaz | Recorridos principales a 320 px y escritorio, teclado y lector de pantalla. Verificar carga, vacío, error, conflicto, reintento y contacto externo. Contrastar textos, foco, etiquetas y mensajes de estado |
| PA-07 | Operación | Carga con escenario RNF-04, restauración de base y archivos, revisión de gastos y ensayo de flujo con comercios piloto. Registrar evidencia por requisito y responsable |
| PA-08 | Catálogo y promociones | Las grafías de Coca-Cola encuentran la misma marca, las presentaciones distintas quedan separadas y «promo de fernet» encuentra combos por sus componentes. Probar vigencia, precio comparativo y componente pausado |
| PA-09 | Modalidad y contacto | Un carrito combina retiro sin domicilio y envío con dirección manual. Denegar ubicación mantiene la revisión disponible. Un comercio ajeno al envío no recibe los datos privados |
| PA-10 | Confirmación, aviso e indicadores | Dos acciones sobre la misma versión producen una confirmación y una tarea elegible. El aviso muestra dirección e ítems y permite coordinar. Un pedido con alcohol en un combo no habilita aviso ni derivación. Cancelar, cambiar el número o revocar el permiso antes del despacho omite la tarea. Fallar el envío conserva el estado del pedido. El tablero cuenta una sola aprobación y distingue completados |
| PA-11 | Navegación y surtido | Gastronomía muestra rotiserías, restaurantes y bares, y Kioscos muestra kioscos y despensas. Una gaseosa común conserva su identidad en ambos rubros y cada comercio conserva precio y surtido propios. Cambiar de entrada mantiene el carrito |
| PA-12 | Ajustes y vencimiento | Solo el cliente titular acepta la propuesta vigente. Una revisión anterior o rechazada no permite confirmar. Una carrera entre confirmación y vencimiento o cancelación produce una sola transición. La suspensión de publicación permite atender los subpedidos existentes |
| PA-13 | Registro y teléfono | Exigir correo confirmado y teléfono vinculado por SMS. Probar código vencido o repetido, dos cuentas concurrentes con el mismo número en formatos equivalentes y un fallo de entrega que deje el alta incompleta sin perder el carrito |
| PA-14 | Alta comercial y horarios | Denegar solicitudes pendientes, rechazadas, vencidas o revocadas y correo no coincidente. Reintentar tras consumir aprobación devuelve una sola ficha en borrador y membresía. Validar publicación con datos completos, logo, varios turnos, 24 horas, cierre y tramo nocturno |
| PA-15 | Relevancia y ocultación | Escenario de extremo a extremo. Comprobar los tres bloques siguientes |
| PA-15A | B1 · Permisos y ficha | Verificar peso inicial 50, rango 1–100, auditoría y denegación a operador. Ocultar y restaurar la ficha y logo. Un enlace de imagen consultado previamente deja de servir el archivo tras ocultar |
| PA-15B | B2 · Catálogo y rotación | Probar pesos iguales y reparto esperado 50 %, 25 %, 25 % con valores 100, 50 y 50. Un cursor abierto y respuestas que usaron caché excluyen al comercio oculto, sus ofertas e imágenes |
| PA-15C | B3 · Carrito e historial | En carrera entre ocultar y enviar, el pedido ya registrado permanece accesible y un envío posterior al bloqueo exige revisar el carrito. Restaurar conserva publicación, pausa y membresías |
| PA-16 | Demostración completa | Ejecutar en Deán Funes con comercios ficticios de ambos rubros. Probar registro con correo y SMS reales a destinatarios autorizados, alta comercial, ofertas y promociones, carrito multicomercio, confirmación y rechazo, WhatsApp con dirección e ítems, historial y acciones administrativas |

QA revisará criterios con fixtures sintéticos. Cubrir reglas de importes, vigencia y transiciones con pruebas unitarias. Validar PostgreSQL, autorización y carreras en integración. Usar navegador aislado y pruebas de extremo a extremo para recorridos cliente y comercio. Cerrar los P0 con evidencia, revisión independiente y aceptación de producto en validación. Este documento define pruebas para desarrollo y piloto.

## 33. Registro de decisiones y validaciones del piloto

DP-01 a DP-13 tienen un criterio de implementación inicial y una validación operativa asignada. Esta tabla conserva los temas y su trazabilidad. Los criterios de arranque adoptados están en el [cierre de definición del backend](DondePido_Definicion_Backend_MVP.md).

| ID | Decisión | Recomendación inicial | Bloquea y responsable sugerido |
| --- | --- | --- | --- |
| DP-01 | Ciudad y alcance de demostración y piloto | Deán Funes, Córdoba, Argentina. ARS y zona `America/Argentina/Cordoba`. Comercio ficticio de cada rubro para demostrar. Los reales se incorporan después de la presentación | Catálogo y piloto · Producto y Operación |
| DP-02 | Taxonomía, variantes, plazo de altas y pertenencia de comercios mixtos | Gastronomía y Kioscos confirmados. Sembrar catálogo con el surtido real, incorporar faltantes con alta asistida y usar alias y comparación exacta por identidad verificada | RF-04, RF-16, RF-21, RF-28 · Producto y Operación |
| DP-03 | Precio comparativo, vigencia, redondeo y compatibilidad de promociones | Combo por debajo de precios individuales efectivos y una rebaja por oferta. Disponibilidad manual y revisión de cambios al enviar | RF-05, RF-09, RF-17, RF-22, RF-27 · Producto y comercios |
| DP-04 | Modalidades, cobertura, dirección, costo, plazo y canal alternativo | Retiro o envío por comercio, dirección manual y ubicación optativa. Cargos externos separados, con aceptación si se informan al aprobar | RF-13, RF-23, RF-24 · Producto y Operación |
| DP-05 | Cambios de condiciones, falta de respuesta, cancelación, suspensión y cierre | Ajustes de entrega aceptados por revisión. Aviso de espera a los 10 minutos y vencimiento a los 60 como valores iniciales. Validar esos plazos con comercios piloto | RF-12, RF-15, RF-20, RF-25 · Producto y Operación |
| DP-06 | Método de acceso, recuperación, MFA, membresías y soporte | Correo verificado y contraseña, nombre, apellido y teléfono único verificado por SMS. TOTP para operadores y administración. Recuperación por correo y permiso de soporte separado | RF-07, RF-29, RF-30 y RNF-01 · Producto, Backend y QA |
| DP-07 | Persistencia, reintento y límites del carrito, envío conjunto y conflictos | Borrador local sin datos privados, intento autenticado en servidor al enviar, revisión explícita y envío transaccional. Acordar límites y alcance entre dispositivos | RF-08–11 y RNF-02 · Producto, Frontend, Backend y Database |
| DP-08 | Datos mínimos, visibilidad, conservación y borrado | Política por dato y finalidad, incluidas instantáneas, auditoría, contacto y retención de claves de idempotencia | RF-13, RNF-01, RNF-06 y RNF-10 · Producto y Operación |
| DP-09 | Onboarding, moderación, sucursales y visibilidad comercial | Solicitud y aprobación por correo. Ficha por punto operativo. Relevancia de 1 a 100 y bloqueo reversible desde administración. Los pedidos ya registrados conservan su atención | RF-14, RF-18, RF-31–34 · Operación y Producto |
| DP-10 | Presupuesto, ambientes, recuperación y umbrales de servicio | Validar costos con el escenario comercial, financiar copias de imágenes y ensayar recuperación | Etapas 1 y 4 · DevOps y titular del producto |
| DP-11 | Indicadores, metas del piloto y monetización posterior | Medir respuesta y cobertura primero. Fijar metas tras acordar muestra y periodo. Validar ingresos futuros sin comisión en el MVP | RF-19 y evaluación del piloto · Producto |
| DP-12 | Frontera transaccional y permiso de ejecución | Servidor Next.js y roles dedicados de PostgreSQL con privilegios mínimos y RLS. Probar acceso directo y concurrencia | Etapas 1 y 3 · Tech Lead, Backend, Database y QA |
| DP-13 | Remitente, plantillas, autorización, atención y costos de WhatsApp | Automatización confirmada para el primer día. Probar aviso con dirección e ítems y coordinación con un operador. Mantener pedidos con alcohol en la web como propuesta inicial y validar elegibilidad por rubro | RF-26 · Producto, Backend y Operación |
