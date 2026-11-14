"use client";

import { useEffect, useState } from "react";
import { errorMessage, requestApi } from "../session";
import { ActionForm, FormButton, valueOf } from "./forms";

type ApprovedApplication = {
  id: string;
  email: string;
  sector_code: string;
  observation: string;
  city_id: string;
  status: "approved" | "consumed" | "expired";
  business_id: string | null;
  name: string | null;
  address: string | null;
  publication_status: string | null;
  suspended: boolean;
  verified_contact_phone: string | null;
  verified_contact_at: string | null;
  contact_verification_method: "call" | "whatsapp" | null;
};
type Reference = { cities: { id: string; name: string }[]; sectors: { code: string; name: string }[] };
type ApprovedPage = { items: ApprovedApplication[]; hasNext: boolean };

export function ApprovedApplications({ token, reference }: { token: string; reference: Reference }) {
  const [page, setPage] = useState(0);
  const [revision, setRevision] = useState(0);
  const [data, setData] = useState<ApprovedPage | null>(null);
  const [error, setError] = useState("");

  useEffect(() => {
    let active = true;
    void requestApi<ApprovedPage>("onboarding", { action: "application.approved", page }, token).then(
      (result) => { if (active) { setData(result); setError(""); } },
      (problem) => { if (active) setError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, [page, revision, token]);

  function changePage(next: number) {
    setData(null);
    setError("");
    setPage(next);
  }

  return <>
    {error && <p className="error" role="alert">{error}</p>}
    {!data && !error && <p role="status">Cargando solicitudes aprobadas…</p>}
    {data?.items.length === 0 && <p>No hay solicitudes aprobadas en esta página.</p>}
    {data?.items.map((item) => (
      <ApprovedRow key={item.id} item={item} token={token} reference={reference}
        refresh={() => setRevision((current) => current + 1)} />
    ))}
    {(page > 0 || data?.hasNext) && (
      <nav className="gestion-nav" aria-label="Páginas de solicitudes aprobadas">
        <button className="button secondary" disabled={page === 0} onClick={() => changePage(page - 1)}>Anterior</button>
        <span>Página {page + 1}</span>
        <button className="button secondary" disabled={!data?.hasNext} onClick={() => changePage(page + 1)}>Siguiente</button>
      </nav>
    )}
  </>;
}

function ApprovedRow({ item, token, reference, refresh }: {
  item: ApprovedApplication; token: string; reference: Reference; refresh: () => void;
}) {
  const [editing, setEditing] = useState(false);
  const [verifyingContact, setVerifyingContact] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [suspended, setSuspended] = useState<boolean | null>(null);
  const isSuspended = suspended ?? item.suspended;
  const hasBusiness = item.business_id !== null;
  const expired = item.status === "expired";
  const status = expired ? "Vencida" : isSuspended ? "Suspendido" : !hasBusiness ? "Alta pendiente"
    : item.publication_status === "catalog_only" ? "Catálogo visible"
      : item.publication_status === "published" ? "Visible" : "Borrador";

  useEffect(() => {
    setSuspended(null);
  }, [item.suspended]);

  async function toggleSuspension() {
    if (busy) return;
    setBusy(true);
    setError("");
    try {
      await requestApi("onboarding", {
        action: "application.suspend", applicationId: item.id, suspended: !isSuspended,
      }, token);
      setSuspended(!isSuspended);
      refresh();
    } catch (problem) {
      setError(errorMessage(problem));
    } finally {
      setBusy(false);
    }
  }

  return <article className="approved-row">
    <h3>{item.name ?? item.email}</h3>
    {item.name && <p>{item.email}</p>}
    <p>{reference.sectors.find((sector) => sector.code === item.sector_code)?.name ?? item.sector_code} · {status}</p>
    <p>{item.verified_contact_at && item.verified_contact_phone
      ? `Teléfono verificado: ${item.verified_contact_phone} · ${item.contact_verification_method === "call" ? "Llamada" : "WhatsApp"}`
      : "Teléfono comercial pendiente de validación manual"}</p>
    {!expired && (
      <div className="gestion-nav">
        <button type="button" className="button secondary" role="switch" aria-checked={isSuspended}
          aria-label={`Suspender ${item.name ?? item.email}`} disabled={busy} onClick={() => void toggleSuspension()}>
          {busy ? "Guardando…" : isSuspended ? "Reactivar" : "Suspender"}
        </button>
        <button type="button" className="button secondary" aria-expanded={editing} onClick={() => setEditing(!editing)}>
          <span aria-hidden="true">✎ </span>Editar
        </button>
        <button type="button" className="button secondary" aria-expanded={verifyingContact}
          onClick={() => setVerifyingContact(!verifyingContact)}>Verificar teléfono</button>
      </div>
    )}
    {error && <p className="error" role="alert">{error}</p>}
    {verifyingContact && !expired && (
      <ActionForm success="Validación registrada." submit={async (form) => {
        await requestApi("onboarding", {
          action: "application.verify_contact", applicationId: item.id, phone: valueOf(form, "phone"),
          method: valueOf(form, "method"), confirmed: form.has("confirmed"),
        }, token);
        refresh();
      }}>
        <label className="field">Teléfono comercial con código de país
          <input name="phone" type="tel" autoComplete="off" placeholder="+54 9 …"
            defaultValue={item.verified_contact_phone ?? ""} maxLength={40} required />
        </label>
        <label className="field">Cómo lo verificaste<select name="method" required defaultValue="">
          <option value="" disabled>Elegí un método</option>
          <option value="whatsapp">WhatsApp</option><option value="call">Llamada</option>
        </select></label>
        <label><input type="checkbox" name="confirmed" required /> Confirmo que el comercio controla este número.</label>
        <FormButton>Registrar validación</FormButton>
      </ActionForm>
    )}
    {editing && !expired && (
      <ActionForm success="Cambios guardados." submit={async (form) => {
        await requestApi("onboarding", {
          action: "application.edit", applicationId: item.id, email: valueOf(form, "email"),
          cityId: valueOf(form, "cityId"), sector: valueOf(form, "sector"),
          observation: valueOf(form, "observation"),
          name: hasBusiness ? valueOf(form, "name") : null, address: hasBusiness ? valueOf(form, "address") : null,
        }, token);
        refresh();
      }}>
        <label className="field">Correo<input type="email" name="email" defaultValue={item.email} maxLength={254} readOnly={hasBusiness} required /></label>
        <label className="field">Rubro<select name="sector" defaultValue={item.sector_code} required>
          {reference.sectors.map((sector) => <option key={sector.code} value={sector.code}>{sector.name}</option>)}
        </select></label>
        <label className="field">Ciudad<select name="cityId" defaultValue={item.city_id} required>
          {reference.cities.map((city) => <option key={city.id} value={city.id}>{city.name}</option>)}
        </select></label>
        <label className="field">Observación<textarea name="observation" defaultValue={item.observation} maxLength={2000} required /></label>
        {hasBusiness && <>
          <label className="field">Nombre del comercio<input name="name" defaultValue={item.name ?? ""} maxLength={160} required /></label>
          <label className="field">Dirección<input name="address" defaultValue={item.address ?? ""} maxLength={400} required /></label>
        </>}
        <FormButton>Guardar cambios</FormButton>
      </ActionForm>
    )}
  </article>;
}
