"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { beginEmailFlow, errorMessage, requestApi, useSession } from "../session";
import "./cuenta.css";

type Factor = { id: string; status: string; factor_type: string };
type AuthUser = { user_metadata?: { first_name?: string; last_name?: string }; factors?: Factor[] };
type AuthTokens = { access_token: string; refresh_token: string; expires_in?: number };
type AuthMode = "login" | "signup" | "recovery";
type AccountDetails = { profile: { firstName: string; lastName: string } | null; phone: string | null };

const destinations: Record<string, string> = {
  "/": "Volver al inicio", "/explorar": "Volver a explorar",
  "/carrito": "Volver al carrito", "/pedidos": "Ir a mis pedidos",
};

function field(data: FormData, name: string) {
  return String(data.get(name) ?? "");
}

export default function Account({ view, destination }: { view?: string; destination?: string }) {
  const { session, ready, notice, auth, saveSession, signOut } = useSession();
  const token = session?.recovery ? undefined : session?.access_token;
  const mode: AuthMode = view === "registro" ? "signup" : view === "recuperar" ? "recovery" : "login";
  const section = view === "telefono" || view === "seguridad" ? view : "perfil";
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [message, setMessage] = useState("");
  const [user, setUser] = useState<AuthUser | null>(null);
  const [details, setDetails] = useState<AccountDetails | null>(null);
  const [phoneChallenge, setPhoneChallenge] = useState<{ id: string; phone: string } | null>(null);
  const [factor, setFactor] = useState<{ id: string; secret: string } | null>(null);
  const accountLink = (target: string) => "/cuenta?" + new URLSearchParams({
    vista: target, ...(destination ? { next: destination } : {}),
  }).toString();

  useEffect(() => {
    if (!token) return;
    let current = true;
    void Promise.all([
      auth<AuthUser>("/user", { token }),
      requestApi<AccountDetails>("onboarding", { action: "profile.mine" }, token),
    ]).then(([account, profile]) => {
      if (current) { setUser(account); setDetails(profile); }
    }, (problem: unknown) => { if (current) setError(errorMessage(problem)); });
    return () => { current = false; };
  }, [auth, token]);

  async function perform(event: FormEvent<HTMLFormElement>, work: (form: FormData) => Promise<void>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    setBusy(true);
    setError("");
    setMessage("");
    try {
      await work(form);
    } catch (problem) {
      setError(errorMessage(problem));
    } finally {
      setBusy(false);
    }
  }

  async function access(form: FormData) {
    const email = field(form, "email").trim();
    const password = field(form, "password");
    if (mode === "login") {
      const result = await auth<AuthTokens>("/token?grant_type=password", { body: { email, password } });
      saveSession(result);
      return;
    }
    const { redirectQuery, ...challenge } = await beginEmailFlow(mode, destination);
    if (mode === "recovery") {
      await auth(`/recover${redirectQuery}`, { body: { email, ...challenge } });
      setMessage("Si existe una cuenta para ese correo, te va a llegar un enlace para cambiar la contraseña.");
      return;
    }
    const data = { first_name: field(form, "firstName"), last_name: field(form, "lastName") };
    await auth(`/signup${redirectQuery}`, { body: { email, password, data, ...challenge } });
    setMessage("Revisá tu correo y abrí el enlace de confirmación en este navegador. Después podés ingresar con tu contraseña.");
  }

  async function resetPassword(form: FormData) {
    const password = field(form, "password");
    if (password !== field(form, "repeatPassword")) throw new Error("Las contraseñas deben coincidir.");
    await auth("/user", { method: "PUT", token: session?.access_token, body: { password } });
    await signOut().catch(() => undefined);
    setMessage("Contraseña actualizada. Ingresá con la nueva contraseña.");
  }

  async function saveProfile(form: FormData) {
    const profile = { firstName: field(form, "firstName").trim(), lastName: field(form, "lastName").trim() };
    await requestApi("onboarding", { action: "profile", ...profile }, token);
    setDetails((current) => ({ phone: current?.phone ?? null, profile }));
    setMessage("Perfil guardado.");
  }

  async function issuePhone(form: FormData) {
    if (!details) throw new Error("Esperá a que cargue tu cuenta.");
    if (!details.profile) {
      const firstName = user?.user_metadata?.first_name?.trim();
      const lastName = user?.user_metadata?.last_name?.trim();
      if (!firstName || !lastName) throw new Error("Completá tu nombre y apellido en Perfil para verificar el teléfono.");
      const profile = { firstName, lastName };
      await requestApi("onboarding", { action: "profile", ...profile }, token);
      setDetails({ ...details, profile });
    }
    const phone = field(form, "phone");
    const id = await requestApi<string>("onboarding", { action: "phone.issue", phone }, token);
    setPhoneChallenge({ id, phone });
    setMessage("Código enviado. Ingresalo para vincular tu teléfono.");
  }

  async function verifyPhone(form: FormData) {
    if (!phoneChallenge) return;
    await requestApi("onboarding", {
      action: "phone.verify", phone: phoneChallenge.phone, challengeId: phoneChallenge.id, code: field(form, "code"),
    }, token);
    setDetails((current) => ({ profile: current?.profile ?? null, phone: phoneChallenge.phone }));
    setPhoneChallenge(null);
    setMessage("Teléfono verificado.");
  }

  const verifiedFactor = user?.factors?.find((item) => item.factor_type === "totp" && item.status === "verified");
  const pendingFactor = user?.factors?.find((item) => item.factor_type === "totp" && item.status === "unverified");
  const factorId = factor?.id ?? verifiedFactor?.id ?? pendingFactor?.id;

  async function enroll() {
    const result = await auth<{ id: string; totp: { secret: string } }>("/factors", {
      token, body: { factor_type: "totp", friendly_name: "DondePido" },
    });
    setFactor({ id: result.id, secret: result.totp.secret });
  }

  async function verifyMfa(form: FormData) {
    if (!factorId) return;
    const challenge = await auth<{ id: string }>(`/factors/${encodeURIComponent(factorId)}/challenge`, { token, body: {} });
    const result = await auth<AuthTokens>(`/factors/${encodeURIComponent(factorId)}/verify`, {
      token, body: { challenge_id: challenge.id, code: field(form, "code") },
    });
    saveSession(result);
    setFactor(null);
    setMessage("Segundo factor verificado. Ya podés entrar al panel de gestión.");
  }

  return (
    <main className="shell cuenta">
      <h1>Mi cuenta</h1>
      <Link href={destination ?? "/"}>{destination ? destinations[destination] : "Volver al inicio"}</Link>
      {!ready && <p role="status">Cargando tu sesión…</p>}
      {notice && <p role="status">{notice}</p>}
      {message && <p role="status">{message}</p>}
      {error && <p className="error" role="alert">{error}</p>}
      {ready && !session && (
        <section className="panel" aria-labelledby="access-heading">
          <h2 id="access-heading">{{ login: "Ingresar", signup: "Crear cuenta", recovery: "Recuperar contraseña" }[mode]}</h2>
          <form onSubmit={(event) => void perform(event, access)}>
            <fieldset disabled={busy}>
              {mode === "signup" && (
                <>
                  <label className="field">Nombre<input name="firstName" autoComplete="given-name" maxLength={100} required /></label>
                  <label className="field">Apellido<input name="lastName" autoComplete="family-name" maxLength={100} required /></label>
                </>
              )}
              <label className="field">Correo electrónico<input name="email" type="email" autoComplete="email" maxLength={254} required /></label>
              {mode !== "recovery" && (
                <label className="field">Contraseña<input name="password" type="password"
                  autoComplete={mode === "signup" ? "new-password" : "current-password"} minLength={6} required /></label>
              )}
              <button className="button" type="submit">{{ login: "Ingresar", signup: "Crear cuenta", recovery: "Enviar enlace" }[mode]}</button>
            </fieldset>
          </form>
          {mode !== "login" && <Link className="button secondary" href={accountLink("ingresar")}>Volver a ingresar</Link>}
          {mode === "login" && (
            <>
              <Link className="button secondary" href={accountLink("registro")}>Crear una cuenta</Link>{" "}
              <Link className="button secondary" href={accountLink("recuperar")}>Olvidé mi contraseña</Link>
            </>
          )}
        </section>
      )}
      {ready && session?.recovery && (
        <section className="panel" aria-labelledby="recovery-heading">
          <h2 id="recovery-heading">Elegir una contraseña nueva</h2>
          <form onSubmit={(event) => void perform(event, resetPassword)}>
            <fieldset disabled={busy}>
              <label className="field">Contraseña nueva<input name="password" type="password" autoComplete="new-password" minLength={6} required /></label>
              <label className="field">Repetí la contraseña<input name="repeatPassword" type="password" autoComplete="new-password" minLength={6} required /></label>
              <button className="button" type="submit">Cambiar contraseña</button>
            </fieldset>
          </form>
        </section>
      )}
      {ready && session && !session.recovery && (
        <>
          <p>{session.email} · <Link href="/gestion">Ir a gestión</Link></p>
          <nav className="account-nav" aria-label="Opciones de cuenta">
            <Link className="button secondary" href={accountLink("perfil")} aria-current={section === "perfil" ? "page" : undefined}>Perfil</Link>
            <Link className="button secondary" href={accountLink("telefono")} aria-current={section === "telefono" ? "page" : undefined}>Teléfono</Link>
            <Link className="button secondary" href={accountLink("seguridad")} aria-current={section === "seguridad" ? "page" : undefined}>Seguridad</Link>
          </nav>
          {section === "perfil" && <section className="panel" aria-labelledby="profile-heading">
            <h2 id="profile-heading">Perfil</h2>
            <form key={user ? "loaded" : "initial"} onSubmit={(event) => void perform(event, saveProfile)}>
              <fieldset disabled={busy || !user}>
                <label className="field">Nombre<input name="firstName" defaultValue={details?.profile?.firstName ?? user?.user_metadata?.first_name}
                  autoComplete="given-name" maxLength={100} required /></label>
                <label className="field">Apellido<input name="lastName" defaultValue={details?.profile?.lastName ?? user?.user_metadata?.last_name}
                  autoComplete="family-name" maxLength={100} required /></label>
                <button className="button" type="submit">Guardar perfil</button>
              </fieldset>
            </form>
          </section>}
          {section === "telefono" && <section className="panel" aria-labelledby="phone-heading">
            <h2 id="phone-heading">Verificar teléfono</h2>
            {details?.phone && <p>Teléfono verificado {details.phone}</p>}
            <form onSubmit={(event) => void perform(event, issuePhone)}>
              <fieldset disabled={busy || !details}>
                <label className="field">Teléfono con código de país<input name="phone" type="tel" autoComplete="tel"
                  placeholder="+54 9 …" maxLength={40} required /></label>
                <button className="button" type="submit">{phoneChallenge ? "Solicitar otro código" : "Enviar código"}</button>
              </fieldset>
            </form>
            {phoneChallenge && (
              <form onSubmit={(event) => void perform(event, verifyPhone)}>
                <fieldset disabled={busy}>
                  <label className="field">Código de seis dígitos<input name="code" inputMode="numeric"
                    autoComplete="one-time-code" pattern="[0-9]{6}" required /></label>
                  <button className="button" type="submit">Verificar teléfono</button>
                </fieldset>
              </form>
            )}
          </section>}
          {section === "seguridad" && <section className="panel" aria-labelledby="mfa-heading">
            <h2 id="mfa-heading">Verificación en dos pasos</h2>
            {session.aal === "aal2" ? <p>Segundo factor verificado en esta sesión.</p> : (
              <>
                {factor && (
                  <p>Agregá esta clave en tu aplicación autenticadora con el nombre DondePido. <code>{factor.secret}</code></p>
                )}
                {!factor && !verifiedFactor && pendingFactor && (
                  <p>Hay una configuración pendiente. Ingresá el código actual de DondePido en tu app autenticadora.</p>
                )}
                {factorId ? (
                  <form onSubmit={(event) => void perform(event, verifyMfa)}>
                    <fieldset disabled={busy}>
                      <label className="field">Código de tu aplicación autenticadora<input name="code" inputMode="numeric"
                        autoComplete="one-time-code" pattern="[0-9]{6}" required /></label>
                      <button className="button" type="submit">Verificar segundo factor</button>
                    </fieldset>
                  </form>
                ) : (
                  <form onSubmit={(event) => void perform(event, enroll)}>
                    <button className="button" type="submit" disabled={busy || !user}>Configurar segundo factor</button>
                  </form>
                )}
              </>
            )}
          </section>}
          <button type="button" className="button secondary" disabled={busy} onClick={() => {
            setPhoneChallenge(null);
            setFactor(null);
            setUser(null);
            setDetails(null);
            void signOut().catch(() => setError("Se cerró la sesión en esta pestaña."));
          }}>Cerrar sesión</button>
        </>
      )}
    </main>
  );
}
