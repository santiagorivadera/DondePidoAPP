"use client";

import { useEffect, useState } from "react";
import { errorMessage, requestApi } from "../session";
import { ActionForm, FormButton, valueOf } from "./forms";

type Variant = {
  id: string;
  name: string;
  category: string;
  brand: string | null;
  presentation: string | null;
  aliases?: string[];
};
type Discount = { id: string; percent: number | null; fixed_price: number | null; starts_at: string; ends_at: string | null };
type Offer = {
  id: string;
  name: string;
  category: string;
  brand: string | null;
  price: number;
  available: boolean;
  kind: "individual" | "combo";
  variant_id: string | null;
  starts_at: string | null;
  ends_at: string | null;
  components: { offerId: string; quantity: number }[];
  discounts: Discount[];
};
type Catalog = { offers: Offer[]; references: Variant[] };

const ars = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" });
export const formatPrice = (minor: number) => ars.format(minor / 100);

export function amountInMinor(input: string, allowZero = false): number {
  const amount = /^([0-9]+)(?:[.,]([0-9]{1,2}))?$/.exec(input);
  const value = amount ? Number(amount[1]) * 100 + Number((amount[2] ?? "").padEnd(2, "0")) : NaN;
  if (!Number.isSafeInteger(value) || value < (allowZero ? 0 : 1) || value > 9_999_999_999) {
    throw new Error("Ingresá un importe válido con hasta dos decimales.");
  }
  return value;
}

function dateValue(date: string | null | undefined) {
  if (!date) return "";
  const value = new Date(date);
  return new Date(value.getTime() - value.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
}

function isoDate(value: string) {
  return value ? new Date(value).toISOString() : null;
}

function variantLabel(variant: Variant) {
  return [variant.name, variant.brand, variant.presentation].filter(Boolean).join(" · ");
}

export function CatalogPanel({ businessId, token, requiresReference }: {
  businessId: string;
  token: string;
  requiresReference: boolean;
}) {
  const [catalog, setCatalog] = useState<Catalog | null>(null);
  const [error, setError] = useState("");
  const [refresh, setRefresh] = useState(0);
  const reload = () => setRefresh((version) => version + 1);
  useEffect(() => {
    let active = true;
    setError("");
    void requestApi<Catalog>("market", { action: "catalog", operation: "mine", businessId }, token).then(
      (data) => { if (active) setCatalog(data); },
      (problem) => { if (active) setError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, [businessId, token, refresh]);
  return (
    <section className="panel" aria-labelledby="catalog-heading">
      <h2 id="catalog-heading">Catálogo</h2>
      {error && <p className="error" role="alert">{error}</p>}
      {!catalog && !error && <p role="status">Cargando catálogo…</p>}
      {catalog && (
        <>
          <details>
            <summary>Agregar producto o combo</summary>
            <OfferForm catalog={catalog} businessId={businessId} token={token} reload={reload} requiresReference={requiresReference} />
          </details>
          {catalog.offers.length === 0 && <p>Todavía no cargaste productos.</p>}
          {catalog.offers.map((offer) => (
            <details key={offer.id}>
              <summary>{offer.name} · {formatPrice(offer.price)} · {offer.available ? "Disponible" : "Pausado"}</summary>
              <OfferForm offer={offer} catalog={catalog} businessId={businessId} token={token} reload={reload} requiresReference={requiresReference} />
              <ActionForm success="Disponibilidad actualizada." submit={async () => {
                await requestApi("market", { action: "catalog", operation: "availability", businessId, offerId: offer.id, available: !offer.available }, token);
                reload();
              }}>
                <FormButton>{offer.available ? "Pausar oferta" : "Reactivar oferta"}</FormButton>
              </ActionForm>
              {offer.kind === "individual" && <DiscountForm businessId={businessId} offer={offer} token={token} reload={reload} />}
            </details>
          ))}
        </>
      )}
    </section>
  );
}

function OfferForm({ offer, catalog, businessId, token, reload, requiresReference }: {
  offer?: Offer;
  catalog: Catalog;
  businessId: string;
  token: string;
  reload: () => void;
  requiresReference: boolean;
}) {
  const [kind, setKind] = useState(offer?.kind ?? "individual");
  const [variantId, setVariantId] = useState(offer?.variant_id ?? "");
  const [components, setComponents] = useState(offer?.components ?? [{ offerId: "", quantity: 1 }, { offerId: "", quantity: 1 }]);
  const variant = catalog.references.find((item) => item.id === variantId);
  const individuals = catalog.offers.filter((item) => item.kind === "individual");

  return (
    <ActionForm success="Oferta guardada." submit={async (form) => {
      await requestApi("market", {
        action: "catalog", operation: "save", businessId, offerId: offer?.id, kind,
        name: variant?.name ?? valueOf(form, "name"),
        category: variant?.category ?? valueOf(form, "category"),
        brand: variant?.brand ?? valueOf(form, "brand"),
        variantId: kind === "individual" ? variantId || null : null,
        price: amountInMinor(valueOf(form, "price")),
        ...(kind === "combo" ? {
          components, startsAt: isoDate(valueOf(form, "startsAt")), endsAt: isoDate(valueOf(form, "endsAt")),
        } : {}),
      }, token);
      reload();
    }}>
      {!offer && <label className="field">Tipo<select value={kind} onChange={(event) => {
        setKind(event.target.value === "combo" ? "combo" : "individual");
        setVariantId("");
      }}><option value="individual">Producto individual</option><option value="combo">Combo</option></select></label>}
      {kind === "individual" && (
        <label className="field">Presentación de catálogo<select required={requiresReference} value={variantId} onChange={(event) => setVariantId(event.target.value)}>
          <option value="">{requiresReference ? "Elegí una presentación" : "Producto propio"}</option>
          {catalog.references.map((item) => <option value={item.id} key={item.id}>{variantLabel(item)}</option>)}
        </select></label>
      )}
      {variant ? <p>{variantLabel(variant)} · {variant.category}</p> : (!requiresReference || kind === "combo") && (
        <label className="field">Nombre<input key={variantId} name="name" defaultValue={offer?.name} maxLength={160} required /></label>
      )}
      {!variant && (
        <div className="gestion-fields">
          <label className="field">Categoría<input name="category" defaultValue={offer?.category} maxLength={100} required /></label>
          <label className="field">Marca<input name="brand" defaultValue={offer?.brand ?? ""} maxLength={120} /></label>
        </div>
      )}
      <label className="field">Precio en pesos<input name="price" inputMode="decimal" defaultValue={offer ? String(offer.price / 100) : ""} required /></label>
      {kind === "combo" && (
        <>
          <h3>Productos del combo</h3>
          {components.map((component, index) => (
            <div key={index} className="gestion-fields">
              <label className="field">Producto {index + 1}<select value={component.offerId} required
                onChange={(event) => setComponents((previous) => previous.map((item, row) => row === index ? { ...item, offerId: event.target.value } : item))}>
                <option value="" disabled>Elegí un producto</option>
                {individuals.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
              </select></label>
              <label className="field">Cantidad<input type="number" min="1" max="20" value={component.quantity || ""} required
                onChange={(event) => setComponents((previous) => previous.map((item, row) => row === index ? { ...item, quantity: Number(event.target.value) } : item))} /></label>
              {components.length > 2 && <button className="button secondary" type="button"
                onClick={() => setComponents((previous) => previous.filter((_, row) => row !== index))}>Quitar producto</button>}
            </div>
          ))}
          {components.length < 20 && <button type="button" className="button secondary"
            onClick={() => setComponents((previous) => [...previous, { offerId: "", quantity: 1 }])}>Agregar producto</button>}
          <Dates startsAt={offer?.starts_at} endsAt={offer?.ends_at} />
        </>
      )}
      <FormButton>{offer ? "Guardar cambios" : "Guardar oferta"}</FormButton>
    </ActionForm>
  );
}

function Dates({ startsAt, endsAt }: { startsAt?: string | null; endsAt?: string | null }) {
  return (
    <div className="gestion-fields">
      <label className="field">Desde (hora local)<input name="startsAt" type="datetime-local" defaultValue={dateValue(startsAt)} /></label>
      <label className="field">Hasta (hora local)<input name="endsAt" type="datetime-local" defaultValue={dateValue(endsAt)} /></label>
    </div>
  );
}

function DiscountForm({ businessId, offer, token, reload }: {
  businessId: string; offer: Offer; token: string; reload: () => void;
}) {
  const [kind, setKind] = useState("percent");
  return (
    <>
      <h3>Rebajas</h3>
      <ActionForm success="Rebaja guardada." submit={async (form) => {
        await requestApi("market", {
          action: "catalog", operation: "discount", businessId, offerId: offer.id,
          ...(kind === "percent" ? { percent: Number(valueOf(form, "discount")) } : { price: amountInMinor(valueOf(form, "discount")) }),
          startsAt: isoDate(valueOf(form, "startsAt")), endsAt: isoDate(valueOf(form, "endsAt")),
        }, token);
        reload();
      }}>
        <label className="field">Tipo de rebaja<select value={kind} onChange={(event) => setKind(event.target.value)}>
          <option value="percent">Porcentaje</option><option value="price">Precio final</option>
        </select></label>
        {kind === "percent"
          ? <label className="field">Porcentaje<input key={kind} name="discount" type="number" min="1" max="99" required /></label>
          : <label className="field">Precio final en pesos<input key={kind} name="discount" inputMode="decimal" required /></label>}
        <Dates />
        <FormButton>Guardar rebaja</FormButton>
      </ActionForm>
      {offer.discounts.map((discount) => (
        <ActionForm key={discount.id} success="Rebaja retirada." submit={async () => {
          await requestApi("market", { action: "catalog", operation: "discount", businessId, offerId: offer.id, discountId: discount.id, remove: true }, token);
          reload();
        }}>
          <p>{discount.percent !== null ? `${discount.percent} %` : formatPrice(discount.fixed_price ?? 0)}
            {" · "}{new Date(discount.starts_at).toLocaleString("es-AR")}
            {" a "}{discount.ends_at ? new Date(discount.ends_at).toLocaleString("es-AR") : "sin fecha de fin"}</p>
          <FormButton>Quitar rebaja</FormButton>
        </ActionForm>
      ))}
    </>
  );
}

export function ReferenceForm({ token }: { token: string }) {
  const [references, setReferences] = useState<Variant[]>([]);
  const [selected, setSelected] = useState("");
  const [revision, setRevision] = useState(0);
  const [error, setError] = useState("");
  const reference = references.find((item) => item.id === selected);
  useEffect(() => {
    let active = true;
    void requestApi<Catalog>("market", { action: "catalog", operation: "mine" }, token).then(
      (catalog) => { if (active) { setReferences(catalog.references); setError(""); } },
      (problem) => { if (active) setError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, [token, revision]);
  return (
    <details>
      <summary>Referencias del catálogo</summary>
      {error && <p className="error" role="alert">{error}</p>}
      <label className="field">Referencia<select value={selected} onChange={(event) => setSelected(event.target.value)}>
        <option value="">Crear referencia</option>
        {references.map((item) => <option value={item.id} key={item.id}>{variantLabel(item)}</option>)}
      </select></label>
      <ActionForm key={`${selected}:${Boolean(reference)}`} success="Referencia guardada." submit={async (form) => {
        const result = await requestApi<{ id: string }>("market", {
          action: "catalog", operation: "reference", variantId: selected || null,
          name: valueOf(form, "name"), category: valueOf(form, "category"), brand: valueOf(form, "brand"),
          presentation: valueOf(form, "presentation"), aliases: valueOf(form, "aliases").split(",").map((alias) => alias.trim()).filter(Boolean),
        }, token);
        setSelected(result.id);
        setRevision((version) => version + 1);
      }}>
        <label className="field">Nombre<input name="name" defaultValue={reference?.name} maxLength={160} required /></label>
        <label className="field">Categoría<input name="category" defaultValue={reference?.category} maxLength={100} required /></label>
        <label className="field">Marca<input name="brand" defaultValue={reference?.brand ?? ""} maxLength={120} /></label>
        <label className="field">Presentación<input name="presentation" defaultValue={reference?.presentation ?? ""} maxLength={160} /></label>
        <label className="field">Alias separados por comas<input name="aliases" defaultValue={reference?.aliases?.join(", ")} /></label>
        <FormButton>Guardar referencia</FormButton>
      </ActionForm>
    </details>
  );
}
