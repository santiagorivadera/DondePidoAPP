# DondePido. — Relevamiento funcional del cliente y del comercio

**11 de noviembre de 2026 · Versión 0.9** · [Especificación](DondePido_Analisis_y_Especificacion_del_Sistema.md) · [Matriz](DondePido_Matriz_de_Requerimientos.md).

La [definición de arranque](DondePido_Definicion_Backend_MVP.md) fija las reglas operativas, los estados y el remitente inicial para desarrollar este flujo.

La solicitud confirma las entradas «Gastronomía» y «Kioscos», la carga por categorías, combos, rebajas, retiro o envío, ubicación opcional, gestión de pedidos y estadísticas. Ningún pedido descuenta stock. Desde el primer día del piloto, la confirmación del comercio dispara un aviso automático por WhatsApp con el número de pedido, los productos o el combo, la dirección correspondiente y una vía para coordinar. Las reglas de moderación y los detalles de operación siguen sujetos a validación con los comercios piloto.

## 1. Catálogo común y ofertas de cada comercio

**Entradas principales confirmadas.** La portada muestra dos accesos grandes. **Gastronomía** reúne rotiserías, restaurantes y bares. **Kioscos** reúne kioscos y despensas. Cada entrada muestra los comercios, categorías, productos y promociones de ese rubro en la ciudad elegida. Propuesta inicial de un rubro principal por comercio, con posibilidad de validar un segundo cuando corresponda. Cambiar de rubro conserva el carrito.

**Recomendación.** El rubro organiza la navegación y la categoría describe el producto. Una misma gaseosa puede venderse en un bar y en un kiosco usando la misma ficha de producto. Cada negocio elige qué vende y configura sus propios precios, promociones y disponibilidad. Gastronomía puede priorizar platos y combos propios. Kioscos puede priorizar marcas, tamaños, envases y otros atributos de productos envasados. Administración mantiene categorías, marcas, nombres canónicos, presentaciones y sinónimos compartidos.

| Dato | Quién lo mantiene | Regla propuesta |
| --- | --- | --- |
| Categoría | Administración, con sugerencias del comercio | Selector con jerarquía corta. Ejemplo «Bebidas › Gaseosas». Mostrar y filtrar por identidad de categoría |
| Marca | Administración, con sugerencias del comercio | Nombre público con escritura oficial, como «Coca-Cola». Opcional para productos genéricos y platos propios |
| Nombre y presentación | Catálogo común para envasados. Comercio para platos propios, con categoría común | Inicial mayúscula en nombres comunes, como «Gaseosa» o «Lomito completo». Mantener ortografía, tildes, nombres oficiales y unidades. Mostrar atributos separados, como marca, variante, tamaño y envase |
| Precio y disponibilidad | Cada comercio | Precio regular exacto y estado disponible, pausado o borrador. El comercio puede pausar y reactivar. El pedido carece de efecto sobre inventario, cupos y disponibilidad publicada |
| Alias de búsqueda | Administración, con propuestas a partir de búsquedas | Sinónimos y grafías verificadas para recuperar resultados. Un alias ambiguo puede llevar a varias coincidencias y requiere selección explícita para vincular un producto |

**Alta desde el panel.** Para el piloto, armar una base inicial con el surtido real de los comercios participantes y ampliarla a medida que carguen productos. «Agregar producto» permite buscar por nombre, marca, presentación o código de barras si existe y elegir la coincidencia exacta. La oferta se publica al completar precio y disponibilidad. Si falta el producto o la marca, «Crear y solicitar alta» conserva todos los datos de la oferta en un borrador y sugiere coincidencias. Operación puede vincular a una ficha existente o aprobar una nueva. El comercio ve el estado y retoma su oferta con los datos ya ingresados. Acordar un responsable y un plazo de revisión antes del piloto. Para preparaciones propias, permitir publicación con nombre, descripción y categoría común sin esperar un registro compartido por plato. Evaluar después del piloto si conviene publicar envasados provisionales fuera de la comparación exacta.

**Comparación y búsqueda.** `coca cola`, `CoCAcolA` y `coca-cola` deben encontrar la marca canónica «Coca-Cola». La búsqueda tolera diferencias de mayúsculas, tildes y separadores y admite alias curados. La normalización se usa para buscar y advertir duplicados. La equivalencia exacta requiere verificar marca cuando aplique, variante, contenido, formato y unidad de venta. `1,5 L` y `1500 ml` pueden representar el mismo contenido. Una botella de 500 ml, una versión Zero y un pack siguen siendo presentaciones distintas. Los lomitos de diferentes locales se muestran como alternativas con porción, ingredientes o descripción.

La búsqueda de «promo de fernet» consulta promociones vigentes y encuentra tanto rebajas de fernet como combos que incluyan un producto de esa categoría, aunque el título del combo sea «Combo para compartir». Mostrar qué componente coincidió. Los filtros usan identificadores comunes de categoría y marca. Una búsqueda de ofertas y promociones respeta ciudad, vigencia y disponibilidad.

## 2. Promociones y rebajas en el panel

| Modalidad | Flujo del comercio | Vista del cliente |
| --- | --- | --- |
| Combo | «Crear combo» → seleccionar al menos dos ofertas propias y sus cantidades → escribir título → fijar precio total y vigencia → vista previa → publicar o programar | Nombre, contenido y cantidades, precio total destacado y, en un bloque secundario «Precio por separado», los importes individuales tachados y su suma como referencia cuando el combo representa un ahorro real |
| Rebaja individual | Elegir producto publicado → «Rebaja» → elegir porcentaje o precio final fijo → elegir sin fecha de fin o fecha y hora de fin → vista previa → activar o programar | Precio regular tachado y precio rebajado. Si es por tiempo limitado, etiqueta «Descuento exprés», fecha u hora de fin y, si se muestra un contador, mantener disponible la hora exacta. Si es indefinida, mostrar «Rebaja» sin contador |

- **Comparación de precios.** Para el combo, «por separado» usa los precios vigentes que el cliente pagaría comprando cada componente individualmente en ese mismo comercio, incluidas sus rebajas individuales si aplican. Si no hay referencia comprobable o el combo deja de ahorrar, retirar la presentación como promoción y avisar al comercio para ajustar el precio o pausar. La vista previa muestra los precios unitarios y el importe por cantidad. Para la rebaja individual, exigir precio final positivo y menor que el regular. Aplicar el porcentaje con una regla de redondeo monetario única, propuesta a la unidad mínima más cercana con mitades hacia arriba.
- **Vigencia y compatibilidad.** Usar horario local en la interfaz, con inicio inclusivo y fin exclusivo calculados por el servidor. Una rebaja efectiva por oferta. El combo tiene su precio propio y las rebajas individuales no se vuelven a aplicar a ese precio. El comercio puede programar, pausar o terminar una promoción. Si un componente se pausa o se despublica, el combo deja de ser solicitable. Si una rebaja fija deja de ser menor que el precio regular, retirar la rebaja de la vista pública y mostrar el precio regular vigente.
- **Pedido e historial.** El combo se solicita como una línea, con su composición y cantidad de combos. Al enviar se revalidan precio, vigencia, composición y disponibilidad. Si cambió una condición del carrito, se muestran diferencias y se pide revisar. Después del envío, conservar en el subpedido nombre, componentes, cantidades, precios de referencia y final aceptado, junto con la promoción aplicada. Cambios posteriores de catálogo no cambian el pedido.

**Ejemplo ilustrativo.** «Combo lomito + gaseosa» a **$10.000**. En el bloque secundario se lee «Precio por separado» con «Lomito ~~$9.000~~ · Gaseosa ~~$2.000~~ · Total ~~$11.000~~». En una rebaja individual, «Gaseosa 500 ml · Descuento exprés hasta las 21:00 · ~~$2.500~~ **$2.000**».

## 3. Recorrido del cliente

**Crear cuenta.** Ingresar nombre, apellido, correo y contraseña. Confirmar el correo y luego ingresar el código recibido por SMS para vincular el teléfono. El mismo número solo puede estar activo en una cuenta. Queda disponible como destino del aviso de pedido por WhatsApp, con autorización de mensajes. Se puede explorar y armar el carrito antes de crear cuenta. Para enviar se exige el registro completo.

1. **Descubrir.** Entrar en «Gastronomía» o «Kioscos» en Deán Funes, primera ciudad habilitada. Buscar por producto, marca, categoría o comercio, y filtrar promociones en el rubro seleccionado. Desde una tarjeta de promoción se puede abrir el detalle o tocar «Solicitar». Esa acción agrega la selección y abre la revisión del carrito. El envío final es explícito.
2. **Elegir por comercio.** Ver los productos y su subtotal agrupados. En cada comercio, seleccionar «Retiro» o «Envío» entre las modalidades que ofrece. En retiro, mostrar local, dirección pública e indicaciones. En envío, pedir dirección solo a los comercios seleccionados para enviar. Se puede aplicar la misma dirección a varios grupos mediante una acción explícita.
3. **Ingresar la dirección.** Ofrecer calle, altura y localidad editables, y piso, departamento o referencia si corresponde. «Usar mi ubicación actual» pide permiso una vez, muestra la posición obtenida y solicita confirmarla o corregirla. Con mapa, ofrecer ajuste del punto y edición textual. Si no hay conversión de coordenadas a dirección, conservar el punto opcional y pedir la dirección escrita. El camino manual funciona si el permiso se deniega, la posición es imprecisa o falla. Compartir solo al enviar y solo con el comercio destinatario de la entrega. [Especificación de Geolocalización del W3C](https://www.w3.org/TR/geolocation/).
4. **Enviar y seguir.** Revisar productos, precio, modalidad, dirección si aplica y costo o plazo de envío si se conoce. Identificarse, elegir si quiere recibir avisos por WhatsApp y enviar. Mostrar «Solicitud recibida» y la referencia de cada comercio. Un resultado incierto se recupera con el mismo intento y los datos privados quedan fuera del almacenamiento local persistente.
5. **Recibir confirmación y coordinar.** Cuando el comercio confirma las condiciones solicitadas, DondePido muestra «Confirmado» y envía el aviso por WhatsApp si el pedido y el destinatario son elegibles. El cliente puede coordinar con el comercio por ese canal sin otro paso de confirmación. Si el comercio necesita cambiar el precio, el cargo de envío o la dirección, debe obtener aceptación explícita antes de confirmar. Si rechaza, el cliente ve el motivo comunicable y puede volver al catálogo.

## 4. Recorrido del comercio

**Solicitar acceso.** «Quiero registrar mi comercio» pide el correo de registro, rubro y una observación para explicar qué local es. Administración revisa la solicitud en su panel. Si la aprueba, la persona inicia sesión o se registra con ese mismo correo verificado. Completa el nombre del local, rubro, dirección, días y horarios y foto de la marca o logo. Si ya era cliente, conserva su cuenta. El servidor comprueba la aprobación antes de permitir el alta comercial.

1. **Preparar y publicar la ficha.** La ficha empieza en borrador. Editar días y horarios con varios turnos, tramos nocturnos, días cerrados o atención de 24 horas. Configurar canal comercial y al menos una modalidad para publicar. El comercio puede pausar la recepción de solicitudes o la disponibilidad de una oferta desde el panel. La ficha visible informa cuándo la recepción está pausada.
2. **Atender la bandeja.** Ver primero los nuevos, con cantidad y antigüedad. Abrir el detalle con productos o combo, precio solicitado, modalidad, datos mínimos y dirección o ubicación solo para envío. Verificar si puede preparar el pedido y cumplir el retiro o la entrega.
3. **Resolver.** «Confirmar pedido» comprueba que el comercio puede respetar productos, precio y condiciones aceptadas. Para agilizar el envío, se propone configurar zonas y tarifas del comercio para mostrarlas antes de que el cliente solicite. Si falta definir un cargo o hay un cambio material, mantener «Recibido» mientras se coordina y se registra la aceptación del cliente. «Rechazar» pide un motivo breve y comunicable, como indisponibilidad o fuera de cobertura.
4. **Coordinar y cerrar.** Al confirmar, la bandeja muestra el estado del aviso y permite llegar a la conversación o al canal de atención. El comercio prepara el pedido y registra «Completado» al entregarlo o retirarlo. El historial se filtra por fecha, estado y modalidad.

## 5. Estados y responsabilidades

| Estado visible | Evento y actor | Siguiente paso |
| --- | --- | --- |
| Recibido | Cliente envía una solicitud validada | Comercio confirma o rechaza. Si falta aceptar un cambio material, se mantiene recibido hasta resolverlo |
| Rechazado | Comercio rechaza con motivo | El cliente ve el resultado. El subpedido termina |
| Confirmado | Comercio confirma la versión vigente acordada | Se encola el aviso de WhatsApp para pedidos elegibles. El comercio prepara y el cliente puede coordinar |
| Completado | Comercio registra retiro o entrega realizada | Cierre operativo que alimenta indicadores de cumplimiento |
| Cancelado o vencido | El cliente cancela una solicitud recibida, vence su plazo o el operador cancela un pedido confirmado con motivo | Registrar actor o regla, motivo y momento |

La aprobación comercial y «Confirmado» son el mismo evento. Registrar actor y versión. El estado agrupado del carrito deriva de los subpedidos. La aceptación de una modificación material es una excepción al flujo normal y se registra antes de confirmar.

## 6. WhatsApp automático desde el primer día

**Flujo.** Al confirmar, DondePido registra la decisión y encola el aviso en la misma transacción para subpedidos elegibles. Un proceso posterior envía el aviso al número verificado y autorizado. El cliente ve «Confirmado» en DondePido aunque el mensaje tarde. WhatsApp informa el resultado y permite coordinar con el comercio.

**Ejemplo para envío.** «Tu pedido #D123 en Rotisería del Centro se confirmó. Envío a Av. Ejemplo 123, Localidad. Pedido: 1 combo de lomito con gaseosa y 2 empanadas. Si necesitás coordinar la entrega, hablá con el comercio». Para retiro, usar la dirección pública del local y las indicaciones aplicables. Antes de enviar la solicitud, informar que el aviso incluirá el domicilio de entrega y el detalle de productos. Las coordenadas y referencias sensibles quedan en el detalle privado. Las variables se toman del subpedido confirmado, no del catálogo vigente.

**Dependencias.** WhatsApp Business Platform oficial, remitente identificado, número del destinatario verificado, autorización de contacto y plantilla de inicio aprobada. Para el piloto se adopta un remitente central de DondePido. El aviso identifica al comercio y dirige al cliente a su canal verificado desde el detalle del pedido o, si la plantilla aprobada lo permite, directamente. Probar que el cliente llega a un operador del comercio. [Política de WhatsApp Business](https://whatsappbusiness.com/policy/) · [Mensajes de actualización de pedidos](https://whatsappbusiness.com/products/conversation-categories/utility/) · [Precios de WhatsApp Business Platform](https://whatsappbusiness.com/products/platform-pricing/).

**Fernet y otros productos regulados.** Meta lista a Argentina para ciertos mensajes sobre alcohol en su plataforma, con requisitos de edad y cumplimiento local. También prohíbe ofrecer experiencias de compra o venta de esos productos en WhatsApp. La propuesta inicial es mantener en DondePido la solicitud y confirmación de subpedidos que incluyan alcohol, incluidos combos, y excluirlos del aviso y de la derivación a WhatsApp mientras se valide el alcance permitido. La habilitación de ese rubro en la web depende de los requisitos aplicables al piloto. [Política de WhatsApp Business, §§4–5](https://whatsappbusiness.com/policy/).

**Consistencia y respaldo.** Dos confirmaciones del comercio sobre la misma versión producen un evento y una tarea de aviso. Verificar y deduplicar las actualizaciones del proveedor. Ante resultado de envío incierto, conciliar antes de reenviar. Si el cliente no autoriza WhatsApp o el proveedor falla, el pedido sigue confirmado y visible en la web. La conversación posterior queda para coordinar detalles. Antes del piloto, probar con un número autorizado el envío automático con dirección e ítems y comprobar que la respuesta llegue a un operador del comercio.

## 7. Historial e indicadores del comercio

Filtros iniciales por rango, estado y retiro o envío. Ver número, fecha, productos, promoción, modalidad, estado y subtotal histórico. El tablero distingue recibidos, aprobados o confirmados, rechazados y completados. Una aprobación se cuenta una sola vez como confirmación comercial.

| Pregunta | Indicador propuesto |
| --- | --- |
| ¿Cuántos pedidos acepté o rechacé? | Conteo de subpedidos con decisión en el rango y tasa de aprobación sobre subpedidos decididos. Mostrar pendientes aparte. Un reintento cuenta una vez |
| ¿En qué mes, día y horario hubo más actividad? | Distribuciones por mes, día calendario o día de la semana y franja horaria en la zona del comercio. Alternar demanda por fecha de recepción y cumplimiento por fecha de retiro o entrega registrados |
| ¿Qué productos y combos se pidieron más? | Cantidades solicitadas y completadas por oferta o combo, diferenciando ambas medidas y conservando composición histórica |
| ¿Cuánto valor se completó? | Suma de productos de subpedidos completados, etiquetada «Importe de productos en pedidos completados». Sin registro de cobro, los ingresos efectivamente cobrados quedan fuera de la medición |
| ¿Qué tan rápido respondemos? | Mediana y p90 entre recepción y decisión, tamaño de muestra y pendientes visibles |

Definir un intervalo seleccionado y mostrar «Sin datos» cuando corresponda. Permitir identificar empates al comparar periodos. Mantener acceso por comercio y excluir direcciones, coordenadas y teléfonos del tablero.

## 8. Validaciones antes de implementar

1. **Catálogo y operación.** Validar con operadores cómo cargan envasados y platos, cuánto demoran las altas y quién resuelve duplicados. Probar escritura de marcas y nombres, unidades equivalentes y el caso «promo de fernet» con varios comercios. Revisar categorías habilitadas para el piloto y restricciones del canal para rubros regulados.
2. **Promociones.** Probar combo con rebaja individual activa, componente pausado, cambios durante el carrito, vencimiento, rebaja indefinida, redondeo y edición posterior al pedido. Confirmar si un precio sin ahorro puede quedar como combo regular en una etapa posterior.
3. **Pedido y entrega.** Validar cobertura, costo externo, preparación, plazos y manejo de cambios. Probar retiro sin pedir domicilio, envío con dirección manual, ubicación denegada y dos comercios con modalidades distintas.
4. **WhatsApp.** Antes del lanzamiento, verificar plantilla aprobada, remitente, destinatario, autorización, dirección de envío o retiro, ítems, coordinación con el comercio, reintentos, costos y exclusiones por rubro. Mantener el estado web accesible ante fallos.
5. **Indicadores.** Acordar qué define «más vendido». Probar con eventos sintéticos un pedido confirmado que nunca se completó, uno completado al mes siguiente y un reintento duplicado.
