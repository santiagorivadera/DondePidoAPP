export const businessViews = [
  ["ficha", "Ficha"],
  ["catalogo", "Catálogo y promociones"],
  ["pedidos", "Pedidos"],
  ["indicadores", "Indicadores"],
] as const;

export const adminViews = [
  ["administracion/solicitudes", "Solicitudes"],
  ["administracion/aprobadas", "Aprobadas"],
  ["administracion/visibilidad", "Visibilidad"],
  ["administracion/destacados", "Destacados"],
  ["administracion/referencias", "Referencias"],
] as const;

export type ManagementView = "alta" | (typeof businessViews)[number][0] | (typeof adminViews)[number][0];
