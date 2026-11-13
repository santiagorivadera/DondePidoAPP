import { notFound } from "next/navigation";
import { Management } from "../gestion";
import { adminViews, businessViews } from "../vistas";

export default async function ManagementViewPage({ params, searchParams }: {
  params: Promise<{ vista: string[] }>;
  searchParams: Promise<{ comercio?: string | string[] }>;
}) {
  const { vista } = await params;
  const { comercio } = await searchParams;
  const route = vista.join("/");
  const view = route === "administracion"
    ? "administracion/solicitudes"
    : route === "alta"
      ? "alta"
      : [...businessViews, ...adminViews].find(([id]) => id === route)?.[0];
  if (!view) notFound();
  const requestedBusiness = typeof comercio === "string" ? comercio : undefined;
  return <Management view={view} requestedBusiness={requestedBusiness} />;
}
