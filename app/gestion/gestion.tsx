"use client";

import Link from "next/link";
import { useEffect, useState } from "react";
import { ApiError, errorMessage, requestApi, useSession } from "../session";
import { ActionForm, FormButton, readImageBase64, valueOf } from "./forms";
import { HoursForm } from "./horarios";
import { amountInMinor, CatalogPanel, ReferenceForm } from "./catalogo";
import { IndicatorsPanel, OrdersPanel } from "./pedidos";
import { FeaturedPanel } from "./featured";
import { ApprovedApplications } from "./aprobadas";
import { adminViews, businessViews, type ManagementView } from "./vistas";
import "./gestion.css";

type Reference = { cities: { id: string; name: string }[]; sectors: { code: string; name: string }[] };
type Application = {
  id: string;
  email?: string;
  sector_code: string;
  observation?: string;
  status: string;
};
type ControlBusiness = {
  id: string;
  name: string;
  publication_status: string;
  admin_hidden: boolean;
  relevance: number;
  control_version: string | number;
};
type Business = ControlBusiness & {
  address: string;
  sector_code: string;
  role: string;
  accepting_orders: boolean;
  offers_pickup: boolean;
  offers_delivery: boolean;
  verified_contact: string | null;
  delivery_fee?: number | null;
  weekly_hours?: { weekday: number; intervals: [number, number][] }[];
};

const applicationsStatus: Record<string, string> = {
  pending: "Pendiente", approved: "Aprobada", rejected: "Rechazada",
  revoked: "Revocada", expired: "Vencida", consumed: "Completada",
};

function isDenied(error: unknown) {
  return error instanceof ApiError && error.status === 403;
}

export function Management({ view, requestedBusiness }: { view: ManagementView; requestedBusiness?: string }) {
  const { session, ready } = useSession();
  const token = session && !session.recovery ? session.access_token : undefined;
  const reinforced = Boolean(token && session?.aal === "aal2");
  const [reference, setReference] = useState<Reference>({ cities: [], sectors: [] });
  const [applications, setApplications] = useState<Application[]>([]);
  const [inbox, setInbox] = useState<Application[] | null>(null);
  const [adminAccessDenied, setAdminAccessDenied] = useState(false);
  const [adminBusinesses, setAdminBusinesses] = useState<ControlBusiness[]>([]);
  const [businesses, setBusinesses] = useState<Business[]>([]);
  const [businessesLoaded, setBusinessesLoaded] = useState(false);
  const [revision, setRevision] = useState(0);
  const [errors, setErrors] = useState<string[]>([]);
  const [referenceError, setReferenceError] = useState("");
  const [loading, setLoading] = useState(false);
  const [loadedToken, setLoadedToken] = useState("");

  const refresh = () => setRevision((number) => number + 1);
  const approved = applications.filter((application) => application.status === "approved");
  const business = requestedBusiness ? businesses.find((item) => item.id === requestedBusiness) : businesses[0];
  const businessView = businessViews.find(([id]) => id === view);
  const adminView = adminViews.find(([id]) => id === view);
  const authorized = Boolean(token && loadedToken === token);
  const canManage = authorized && businesses.length > 0;
  const canAdmin = authorized && reinforced && inbox !== null;
  const accessLoaded = ready && (!token || authorized);

  useEffect(() => {
    let active = true;
    void requestApi<Reference>("onboarding", { action: "reference" }).then(
      (data) => { if (active) setReference(data); },
      (problem) => { if (active) setReferenceError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!token) return;
    let active = true;
    setLoading(true);
    async function load() {
      const [own, commerce, queue, controls] = await Promise.allSettled([
        requestApi<Application[]>("onboarding", { action: "application.mine" }, token),
        requestApi<Business[]>("onboarding", { action: "business.mine" }, token),
        reinforced ? requestApi<Application[]>("onboarding", { action: "application.inbox" }, token) : null,
        reinforced ? requestApi<{ businesses: ControlBusiness[] }>("market", { action: "admin.businesses" }, token) : null,
      ] as const);
      if (!active) return;
      setApplications(own.status === "fulfilled" ? own.value : []);
      setBusinesses(commerce.status === "fulfilled" ? commerce.value : []);
      setBusinessesLoaded(commerce.status === "fulfilled");
      setInbox(queue.status === "fulfilled" ? queue.value : null);
      setAdminAccessDenied(queue.status === "rejected" && isDenied(queue.reason));
      setAdminBusinesses(controls.status === "fulfilled" ? controls.value?.businesses ?? [] : []);
      const messages = [own, commerce, queue, ...(queue.status === "fulfilled" && queue.value ? [controls] : [])]
        .flatMap((result) => result.status === "rejected" && !isDenied(result.reason) ? [errorMessage(result.reason)] : []);
      setErrors([...new Set(messages)]);
      setLoadedToken(token ?? "");
      setLoading(false);
    }
    void load();
    return () => { active = false; };
  }, [token, reinforced, revision]);

  const sectorName = (code: string) => reference.sectors.find((sector) => sector.code === code)?.name ?? code;
  const pathFor = (id: ManagementView, businessId = business?.id) => {
    const path = `/gestion/${id}`;
    return businessId && businessViews.some(([candidate]) => candidate === id)
      ? `${path}?comercio=${encodeURIComponent(businessId)}`
      : path;
  };

  return (
    <main className="shell gestion">
      <h1>Gestión comercial</h1>
      {ready && (
        <nav className="gestion-nav" aria-label="Gestión comercial">
          <Link className="button secondary" href={pathFor("alta")} aria-current={view === "alta" ? "page" : undefined}>Alta comercial</Link>
          {canManage && businessViews.map(([id, label]) => (
            <Link className="button secondary" key={id} href={pathFor(id)} aria-current={id === view ? "page" : undefined}>{label}</Link>
          ))}
        </nav>
      )}
      {canAdmin && (
        <nav className="gestion-nav" aria-label="Administración">
          {adminViews.map(([id, label]) => (
            <Link className="button secondary" key={id} href={pathFor(id)} aria-current={id === view ? "page" : undefined}>{label}</Link>
          ))}
        </nav>
      )}
      {(!ready || (token && (loading || loadedToken !== token))) && <p role="status">Cargando gestión…</p>}
      {referenceError && (view === "alta" || view === "administracion/solicitudes") && <p className="error" role="alert">{referenceError}</p>}
      {authorized && errors.map((message) => <p className="error" key={message} role="alert">{message}</p>)}
      {accessLoaded && ((!token && view !== "alta") || (adminView && !reinforced)) && (
        <section className="panel">
          <h2>Acceso a {businessView?.[1].toLowerCase() ?? "administración"}</h2>
          <p>{token ? "Verificá el segundo factor para acceder a esta sección." : "Ingresá a tu cuenta para continuar."}</p>
          <Link className="button" href={token ? "/cuenta?vista=seguridad" : "/cuenta"}>Ir a mi cuenta</Link>
        </section>
      )}
      {authorized && businessView && businessesLoaded && !canManage && !loading && (
        <section className="panel">
          <h2>{businessView[1]}</h2>
          <p>Tu cuenta todavía no tiene un comercio habilitado.</p>
          <Link href={pathFor("alta")}>Consultar mi alta comercial</Link>
        </section>
      )}
      {authorized && reinforced && adminView && adminAccessDenied && !loading && (
        <section className="panel">
          <h2>Administración</h2>
          <p>Tu cuenta no tiene acceso a esta sección.</p>
        </section>
      )}
      {ready && view === "alta" && (
        <section className="panel" aria-labelledby="request-heading">
          <h2 id="request-heading">Solicitar el alta de un comercio</h2>
          {token
            ? <p>La solicitud se vincula con tu correo verificado.</p>
            : <p>Usá el correo con el que vas a registrar tu cuenta. Si ya tenés cuenta, podés <Link href="/cuenta">ingresar</Link>.</p>}
          <ActionForm success="Solicitud recibida. Ingresá con el mismo correo para consultar su estado." submit={async (form) => {
            const fields = { sector: valueOf(form, "sector"), observation: valueOf(form, "observation") };
            if (token) await requestApi("onboarding", { action: "application.submit", ...fields }, token);
            else await requestApi("onboarding", { action: "application.request", email: valueOf(form, "email"), ...fields });
            refresh();
          }}>
            {!token && <label className="field">Correo electrónico<input name="email" type="email" autoComplete="email" maxLength={254} required /></label>}
            <label className="field">Rubro<select name="sector" required defaultValue="">
              <option value="" disabled>Elegí un rubro</option>
              {reference.sectors.map((sector) => <option value={sector.code} key={sector.code}>{sector.name}</option>)}
            </select></label>
            <label className="field">Nombre del local y actividad<textarea name="observation" maxLength={2000} required /></label>
            <FormButton>Enviar solicitud</FormButton>
          </ActionForm>
        </section>
      )}
      {token && authorized && view === "alta" && (
        <>
          <section className="panel" aria-labelledby="applications-heading">
            <h2 id="applications-heading">Mis solicitudes</h2>
            {!loading && applications.length === 0 && <p>Todavía no tenés solicitudes.</p>}
            {applications.length > 0 && <ul>
              {applications.map((application) => <li key={application.id}>{sectorName(application.sector_code)} · {applicationsStatus[application.status] ?? application.status}</li>)}
            </ul>}
            {approved.length > 0 && (
              <ActionForm success="Ficha creada en borrador. Entrá a la ficha para completar los datos y publicarla." submit={async (form) => {
                const file = form.get("logo");
                if (!(file instanceof File) || file.size === 0 || file.size > 256 * 1024) {
                  throw new Error("Elegí un logo de hasta 256 KiB.");
                }
                const logo = await requestApi<string>("onboarding", {
                  action: "logo.upload", mimeType: file.type, base64: await readImageBase64(file),
                }, token);
                await requestApi("onboarding", {
                  action: "application.complete", applicationId: valueOf(form, "applicationId"),
                  name: valueOf(form, "name"), address: valueOf(form, "address"), logo,
                }, token);
                refresh();
              }}>
                <h3>Completar ficha comercial</h3>
                <p className="muted">Podés crear el borrador ahora. Para publicar, administración debe validar el número del comercio por WhatsApp o llamada.</p>
                <label className="field">Solicitud aprobada<select name="applicationId" required>
                  {approved.map((application) => <option key={application.id} value={application.id}>{sectorName(application.sector_code)}</option>)}
                </select></label>
                <label className="field">Nombre del comercio<input name="name" maxLength={160} required /></label>
                <label className="field">Dirección del local<input name="address" maxLength={400} required /></label>
                <label className="field">Logo PNG, JPEG o WebP<input name="logo" type="file" accept="image/png,image/jpeg,image/webp" required /></label>
                <FormButton>Crear ficha</FormButton>
              </ActionForm>
            )}
          </section>
        </>
      )}
      {token && canManage && businessView && (
        <>
          <nav className="gestion-nav" aria-label="Comercios de mi cuenta">
            {businesses.map((item) => (
              <Link className="button secondary" key={item.id} href={pathFor(businessView[0], item.id)}
                aria-current={item.id === business?.id ? "true" : undefined}>{item.name}</Link>
            ))}
          </nav>
          {!business && <p className="error" role="alert">Ese comercio no está disponible para tu cuenta. Elegí otro comercio.</p>}
          {business && (
            <div key={business.id}>
              {view === "ficha" && <BusinessPanel business={business} token={token} refresh={refresh} />}
              {view === "catalogo" && <CatalogPanel businessId={business.id} token={token} requiresReference={business.sector_code === "kioscos"} />}
              {view === "pedidos" && <OrdersPanel businessId={business.id} token={token} />}
              {view === "indicadores" && <IndicatorsPanel businessId={business.id} token={token} />}
            </div>
          )}
        </>
      )}
      {token && canAdmin && adminView && (
        <section className="panel" aria-labelledby="admin-heading">
          <h2 id="admin-heading">{adminView[1]}</h2>
          {view === "administracion/solicitudes" && inbox !== null && (
            <>
              {inbox.length === 0 && <p>No hay solicitudes para revisar.</p>}
              {inbox.map((item) => (
                <details key={item.id}>
                  <summary>{item.email} · {sectorName(item.sector_code)} · {applicationsStatus[item.status] ?? item.status}</summary>
                  <p>{item.observation}</p>
                  {item.status === "pending" && <DecisionForm item={item} cities={reference.cities} token={token} refresh={refresh} />}
                  {item.status === "approved" && (
                    <ActionForm success="Aprobación revocada." submit={async (form) => {
                      await requestApi("onboarding", { action: "application.decide", applicationId: item.id,
                        decision: "revoked", reason: valueOf(form, "reason") }, token);
                      refresh();
                    }}>
                      <label className="field">Motivo de revocación<input name="reason" maxLength={1000} required /></label>
                      <FormButton>Revocar aprobación</FormButton>
                    </ActionForm>
                  )}
                </details>
              ))}
            </>
          )}
          {view === "administracion/aprobadas" && (
            <ApprovedApplications token={token} reference={reference} />
          )}
          {view === "administracion/visibilidad" && (
            <>
              {adminBusinesses.length === 0 && <p>No hay comercios para gestionar.</p>}
              {adminBusinesses.map((item) => <Controls key={item.id} item={item} token={token} refresh={refresh} />)}
            </>
          )}
          {view === "administracion/destacados" && <FeaturedPanel token={token} businesses={adminBusinesses} />}
          {view === "administracion/referencias" && <ReferenceForm token={token} />}
        </section>
      )}
    </main>
  );
}

function DecisionForm({ item, cities, token, refresh }: {
  item: Application; cities: Reference["cities"]; token: string; refresh: () => void;
}) {
  const [decision, setDecision] = useState("approved");
  return <ActionForm success="Decisión guardada." submit={async (form) => {
    await requestApi("onboarding", { action: "application.decide", applicationId: item.id,
      decision, cityId: decision === "approved" ? valueOf(form, "cityId") : null, reason: valueOf(form, "reason") }, token);
    refresh();
  }}>
    <label className="field">Decisión<select value={decision} onChange={(event) => setDecision(event.target.value)}>
      <option value="approved">Aprobar</option><option value="rejected">Rechazar</option>
    </select></label>
    {decision === "approved" && <label className="field">Ciudad<select name="cityId" defaultValue="" required>
      <option value="" disabled>Elegí una ciudad</option>
      {cities.map((city) => <option key={city.id} value={city.id}>{city.name}</option>)}
    </select></label>}
    <label className="field">Motivo<input name="reason" maxLength={1000} required /></label>
    <FormButton>Guardar decisión</FormButton>
  </ActionForm>;
}

function Controls({ item, token, refresh }: { item: ControlBusiness; token: string; refresh: () => void }) {
  return <details>
    <summary>{item.name} · {item.admin_hidden ? "Oculto" : item.publication_status === "draft" ? "Borrador" : "Visible"}</summary>
    <ActionForm key={item.control_version} success="Controles guardados." submit={async (form) => {
      await requestApi("onboarding", { action: "business.controls", businessId: item.id, expectedVersion: item.control_version,
        hidden: form.has("hidden"), relevance: Number(valueOf(form, "relevance")), note: valueOf(form, "note") || null }, token);
      refresh();
    }}>
      <label className="field">Relevancia<input name="relevance" type="number" min="1" max="100" defaultValue={item.relevance} required /></label>
      <label><input name="hidden" type="checkbox" defaultChecked={item.admin_hidden} /> Ocultar todo el contenido</label>
      <label className="field">Motivo interno<input name="note" maxLength={1000} /></label>
      <FormButton>Guardar controles</FormButton>
    </ActionForm>
  </details>;
}

function BusinessPanel({ business, token, refresh }: { business: Business; token: string; refresh: () => void }) {
  return (
      <section className="panel" aria-labelledby="business-heading">
        <h2 id="business-heading">{business.name}</h2>
        <p>{business.address} · {business.admin_hidden ? "Oculto por administración" : business.publication_status === "published" ? "Publicado" : "Borrador"}</p>
        {business.role === "owner" && (
          <>
            <details>
              <summary>Horarios de atención</summary>
              <HoursForm businessId={business.id} token={token} savedHours={business.weekly_hours} />
            </details>
            <details>
              <summary>{business.publication_status === "published" ? "Actualizar modalidades" : "Publicar ficha"}</summary>
              {!business.verified_contact ? (
                <p>Administración debe validar el teléfono comercial por WhatsApp o llamada. Después, actualizá la ficha para publicar.</p>
              ) : <ActionForm key={business.verified_contact} success="Ficha publicada." submit={async (form) => {
                await requestApi("onboarding", { action: "business.publish", businessId: business.id,
                  pickup: form.has("pickup"), delivery: form.has("delivery"),
                  expectedContact: business.verified_contact, confirmPublicContact: form.has("confirm") }, token);
                refresh();
              }}>
                <p className="muted">Guardá los horarios antes de publicar.</p>
                <label><input type="checkbox" name="pickup" defaultChecked={business.offers_pickup} /> Retiro</label>{" "}
                <label><input type="checkbox" name="delivery" defaultChecked={business.offers_delivery} /> Envío</label>
                <label className="field"><span><input type="checkbox" name="confirm" required /> Confirmo que {business.verified_contact} será el contacto del comercio para sus clientes.</span></label>
                <FormButton>Publicar ficha</FormButton>
              </ActionForm>}
            </details>
          </>
        )}
        {business.offers_delivery && (
          <details>
            <summary>Cargo de envío</summary>
            <ActionForm success="Cargo de envío actualizado." submit={async (form) => {
              const fee = valueOf(form, "deliveryFee");
              await requestApi("market", { action: "catalog", operation: "delivery", businessId: business.id,
                deliveryFee: fee ? amountInMinor(fee, true) : null }, token);
              refresh();
            }}>
              <label className="field">Cargo en pesos<input name="deliveryFee" inputMode="decimal"
                defaultValue={typeof business.delivery_fee === "number" ? String(business.delivery_fee / 100) : ""} /></label>
              <p className="muted">Dejalo vacío si el cargo se acuerda con el cliente.</p>
              <FormButton>Guardar cargo</FormButton>
            </ActionForm>
          </details>
        )}
        <ActionForm success="Recepción actualizada." submit={async () => {
          await requestApi("market", { action: "catalog", operation: "reception", businessId: business.id, acceptingOrders: !business.accepting_orders }, token);
          refresh();
        }}>
          <p>{business.accepting_orders ? "Recibiendo solicitudes" : "Recepción pausada"}</p>
          <FormButton>{business.accepting_orders ? "Pausar recepción" : "Activar recepción"}</FormButton>
        </ActionForm>
      </section>
  );
}
