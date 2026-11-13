"use client";

import { useEffect, useState } from "react";
import { errorMessage, requestApi } from "../session";
import { ActionForm, FormButton, readImageBase64, valueOf } from "./forms";

type Banner = {
  id: string;
  title: string;
  business_name: string;
  position: number;
  enabled: boolean;
  starts_at: string | null;
  ends_at: string | null;
};

type Business = { id: string; name: string; publication_status: string; admin_hidden: boolean };
const imageTypes = ["image/png", "image/jpeg", "image/webp"];

function localDate(value: string | null | undefined) {
  if (!value) return "";
  const date = new Date(value);
  return new Date(date.getTime() - date.getTimezoneOffset() * 60_000).toISOString().slice(0, 16);
}

function bannerFields(form: FormData) {
  const starts = valueOf(form, "startsAt");
  const ends = valueOf(form, "endsAt");
  if (starts && ends && ends <= starts) throw new Error("El fin debe ser posterior al inicio.");
  return {
    title: valueOf(form, "title"),
    position: Number(valueOf(form, "position")),
    enabled: form.get("enabled") === "on",
    startsAt: starts ? new Date(starts).toISOString() : null,
    endsAt: ends ? new Date(ends).toISOString() : null,
  };
}

function Fields({ banner }: { banner?: Banner }) {
  return <>
    <label className="field">Título de la promoción<input name="title" maxLength={120} required defaultValue={banner?.title} /></label>
    <div className="gestion-fields">
      <label className="field">Orden de aparición<input name="position" type="number" min="1" max="100" required defaultValue={banner?.position ?? 1} /></label>
      <label className="field">Desde (hora local)<input name="startsAt" type="datetime-local" defaultValue={localDate(banner?.starts_at)} /></label>
      <label className="field">Hasta (hora local)<input name="endsAt" type="datetime-local" defaultValue={localDate(banner?.ends_at)} /></label>
    </div>
    <label className="check"><input name="enabled" type="checkbox" defaultChecked={banner?.enabled ?? true} /> Habilitar en portada</label>
  </>;
}

export function FeaturedPanel({ token, businesses }: { token: string; businesses: Business[] }) {
  const [banners, setBanners] = useState<Banner[] | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const [creation, setCreation] = useState(0);
  const visibleBusinesses = businesses.filter((business) => business.publication_status === "published" && !business.admin_hidden);
  const reload = () => setRevision((value) => value + 1);

  useEffect(() => {
    let active = true;
    void requestApi<{ banners: Banner[] }>("featured", { action: "admin.list" }, token).then(
      (data) => { if (active) { setBanners(data.banners); setError(""); } },
      (problem: unknown) => { if (active) setError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, [token, revision]);

  return (
    <section aria-labelledby="featured-admin-heading">
      <h3 id="featured-admin-heading">Promociones destacadas</h3>
      {error && <p role="alert" className="error">{error} <button type="button" className="button secondary" onClick={reload}>Reintentar</button></p>}
      {!error && banners === null && <p role="status">Cargando promociones destacadas…</p>}
      {banners?.length === 0 && <p>No hay promociones destacadas cargadas.</p>}
      {banners?.map((banner) => (
        <details key={banner.id}>
          <summary>{banner.title} · {banner.business_name} · {banner.enabled ? "Habilitada" : "Desactivada"}</summary>
          <ActionForm success="Cambios guardados." submit={async (form) => {
            await requestApi("featured", { action: "admin.update", id: banner.id, ...bannerFields(form) }, token);
            reload();
          }}>
            <Fields banner={banner} />
            <FormButton>Guardar cambios</FormButton>
          </ActionForm>
        </details>
      ))}
      {visibleBusinesses.length > 0 ? (
        <details>
          <summary>Cargar promoción destacada</summary>
          <ActionForm key={creation} success="Promoción guardada." submit={async (form) => {
            const image = form.get("image");
            if (!(image instanceof File) || !imageTypes.includes(image.type) || !image.size || image.size > 1024 * 1024) {
              throw new Error("Elegí una imagen PNG, JPEG o WebP de hasta 1 MiB.");
            }
            await requestApi("featured", { action: "admin.create", businessId: valueOf(form, "businessId"),
              ...bannerFields(form), mimeType: image.type, base64: await readImageBase64(image) }, token);
            setCreation((value) => value + 1);
            reload();
          }}>
            <label className="field">Comercio<select name="businessId" required defaultValue="">
              <option value="" disabled>Elegí un comercio</option>
              {visibleBusinesses.map((business) => <option key={business.id} value={business.id}>{business.name}</option>)}
            </select></label>
            <Fields />
            <label className="field">Imagen horizontal (hasta 1 MiB)<input name="image" type="file" accept={imageTypes.join(",")} required /></label>
            <FormButton>Cargar promoción</FormButton>
          </ActionForm>
          {creation > 0 && <p role="status">Promoción guardada.</p>}
        </details>
      ) : <p>Publicá un comercio para agregar su promoción a la portada.</p>}
    </section>
  );
}
