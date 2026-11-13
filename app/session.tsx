"use client";

import { createContext, useCallback, useContext, useEffect, useRef, useState, type ReactNode } from "react";

type AuthConfig = { url: string; publicKey: string };
type AuthResult = {
  access_token?: string;
  refresh_token?: string;
  expires_at?: number;
  expires_in?: number;
};
export type Session = {
  access_token: string;
  refresh_token: string;
  expires_at: number;
  aal: "aal1" | "aal2";
  email: string;
  recovery: boolean;
};
type AuthOptions = { method?: "GET" | "POST" | "PUT" | "DELETE"; token?: string; body?: unknown };
type SessionContext = {
  session: Session | null;
  ready: boolean;
  notice: string;
  auth: <T>(path: string, options?: AuthOptions) => Promise<T>;
  saveSession: (result: AuthResult, recovery?: boolean) => void;
  signOut: () => Promise<void>;
};

const sessionKey = "dondepido.session";
const pendingKey = "dondepido.confirmation";
const SessionContext = createContext<SessionContext | null>(null);
let authConfig: Promise<AuthConfig> | undefined;

async function authRequest<T>(path: string, options: AuthOptions = {}): Promise<T> {
  authConfig ??= fetch("/api/auth-config", { cache: "no-store" })
    .then(async (response) => {
      if (!response.ok) throw new Error("El acceso a la cuenta no está disponible.");
      const data: AuthConfig = await response.json();
      if (!data.url || !data.publicKey) throw new Error("El acceso a la cuenta no está configurado.");
      return data;
    })
    .catch((error: unknown) => {
      authConfig = undefined;
      throw error;
    });
  const config = await authConfig;
  const response = await fetch(new URL(`/auth/v1${path}`, config.url), {
    method: options.method ?? (options.body ? "POST" : "GET"),
    headers: {
      apikey: config.publicKey,
      ...(options.token ? { Authorization: `Bearer ${options.token}` } : {}),
      ...(options.body ? { "Content-Type": "application/json" } : {}),
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    cache: "no-store",
    redirect: "error",
  });
  const data = await response.json().catch(() => null);
  if (!response.ok) {
    const code = data?.code ?? data?.error_code;
    if (code === "email_not_confirmed") throw new Error("Confirmá el correo antes de ingresar.");
    if (code === "invalid_credentials") throw new Error("Revisá el correo y la contraseña.");
    if (code === "weak_password") throw new Error("Elegí una contraseña más segura.");
    if (code === "mfa_verification_failed") {
      throw new Error("El código no coincide. Usá el código actual de DondePido en tu app autenticadora y revisá que el celular tenga la hora automática.");
    }
    if (code === "mfa_factor_name_conflict") {
      throw new Error("Ya hay un segundo factor configurado o pendiente. Recargá esta página para continuar con ese factor.");
    }
    if (response.status === 429) throw new Error("Esperá antes de volver a intentar.");
    throw new Error("No pudimos completar la operación de acceso. Revisá los datos e intentá de nuevo.");
  }
  return data as T;
}

export class ApiError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
  }
}

export async function requestApi<T>(
  endpoint: "onboarding" | "market" | "featured",
  payload: Record<string, unknown>,
  token?: string,
): Promise<T> {
  const response = await fetch(`/api/${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(payload),
    cache: "no-store",
  });
  const result = await response.json().catch(() => null);
  if (!response.ok || !result || !("data" in result)) {
    throw new ApiError(response.status, result?.error?.message ?? "No pudimos completar la operación. Volvé a intentar.");
  }
  return result.data as T;
}

export function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : "No pudimos completar la operación.";
}

function base64Url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

export async function beginEmailFlow(purpose: "signup" | "recovery", destination?: string) {
  const verifier = base64Url(crypto.getRandomValues(new Uint8Array(32)));
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
  localStorage.setItem(pendingKey, JSON.stringify({ verifier, purpose, destination, createdAt: Date.now() }));
  return {
    redirectQuery: `?redirect_to=${encodeURIComponent(location.origin)}`,
    code_challenge: base64Url(new Uint8Array(digest)),
    code_challenge_method: "s256",
  };
}

function toSession(result: AuthResult, recovery: boolean): Session {
  if (typeof result.access_token !== "string" || typeof result.refresh_token !== "string") {
    throw new Error("La respuesta de acceso no contiene una sesión válida.");
  }
  const payload = result.access_token.split(".")[1];
  const bytes = Uint8Array.from(atob(payload.replace(/-/g, "+").replace(/_/g, "/")), (char) => char.charCodeAt(0));
  const claims = JSON.parse(new TextDecoder().decode(bytes));
  return {
    access_token: result.access_token,
    refresh_token: result.refresh_token,
    expires_at: result.expires_at ?? Math.floor(Date.now() / 1000) + (result.expires_in ?? 3600),
    aal: claims.aal === "aal2" ? "aal2" : "aal1",
    email: typeof claims.email === "string" ? claims.email : "",
    recovery,
  };
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null);
  const [ready, setReady] = useState(false);
  const [notice, setNotice] = useState("");
  const initialized = useRef(false);

  const storeSession = useCallback((next: Session | null) => {
    try {
      if (next) sessionStorage.setItem(sessionKey, JSON.stringify(next));
      else sessionStorage.removeItem(sessionKey);
    } catch {
      // Keep the current browser tab usable when storage is unavailable.
    }
    setSession(next);
  }, []);

  const saveSession = useCallback((result: AuthResult, recovery = false) => {
    storeSession(toSession(result, recovery));
    setNotice("");
  }, [storeSession]);

  useEffect(() => {
    if (initialized.current) return;
    initialized.current = true;
    async function restore() {
      try {
        const url = new URL(location.href);
        const code = url.searchParams.get("code");
        if (code) {
          url.searchParams.delete("code");
          history.replaceState(history.state, "", url);
          const pending = JSON.parse(localStorage.getItem(pendingKey) ?? "null");
          if (typeof pending?.verifier === "string" && Date.now() - pending.createdAt < 3_600_000) {
            localStorage.removeItem(pendingKey);
            const result = await authRequest<AuthResult>("/token?grant_type=pkce", {
              body: { auth_code: code, code_verifier: pending.verifier },
            });
            saveSession(result, pending.purpose === "recovery");
            const account = new URL("/cuenta", url.origin);
            if (["/", "/explorar", "/carrito", "/pedidos"].includes(pending.destination)) {
              account.searchParams.set("next", pending.destination);
            }
            if (location.pathname + location.search !== account.pathname + account.search) location.replace(account);
            return;
          }
          setNotice("Si confirmaste el correo, ya podés ingresar. Para recuperar la contraseña, abrí el enlace en el mismo navegador donde lo solicitaste.");
        }
        const current: Session | null = JSON.parse(sessionStorage.getItem(sessionKey) ?? "null");
        if (!current?.refresh_token || !current.access_token) return;
        if (current.expires_at * 1000 > Date.now()) {
          setSession(current);
        } else {
          const result = await authRequest<AuthResult>("/token?grant_type=refresh_token", {
            body: { refresh_token: current.refresh_token },
          });
          saveSession(result, current.recovery);
        }
      } catch {
        storeSession(null);
        setNotice("El enlace o la sesión vencieron. Volvé a ingresar o pedí un enlace nuevo.");
      } finally {
        setReady(true);
      }
    }
    void restore();
  }, [saveSession, storeSession]);

  useEffect(() => {
    if (!session) return;
    let active = true;
    const timeout = setTimeout(async () => {
      try {
        const result = await authRequest<AuthResult>("/token?grant_type=refresh_token", {
          body: { refresh_token: session.refresh_token },
        });
        if (active) saveSession(result, session.recovery);
      } catch {
        if (active) {
          storeSession(null);
          setNotice("Volvé a ingresar para continuar.");
        }
      }
    }, Math.max(5000, session.expires_at * 1000 - Date.now() - 60_000));
    return () => {
      active = false;
      clearTimeout(timeout);
    };
  }, [session, saveSession, storeSession]);

  async function signOut() {
    const token = session?.access_token;
    storeSession(null);
    setNotice("");
    if (token) {
      await authRequest("/logout?scope=local", { method: "POST", token });
    }
  }

  return (
    <SessionContext.Provider value={{ session, ready, notice, auth: authRequest, saveSession, signOut }}>
      {children}
    </SessionContext.Provider>
  );
}

export function useSession(): SessionContext {
  const value = useContext(SessionContext);
  if (!value) throw new Error("Falta SessionProvider.");
  return value;
}
