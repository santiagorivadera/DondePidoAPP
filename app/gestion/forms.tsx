"use client";

import { useState, type FormEvent, type ReactNode } from "react";
import { errorMessage } from "../session";

export const valueOf = (form: FormData, key: string) => String(form.get(key) ?? "").trim();

export function readImageBase64(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      if (typeof reader.result === "string") resolve(reader.result.slice(reader.result.indexOf(",") + 1));
      else reject(new Error("No pudimos leer la imagen."));
    };
    reader.onerror = () => reject(new Error("No pudimos leer la imagen."));
    reader.readAsDataURL(file);
  });
}

export function ActionForm({ children, submit, success, className }: {
  children: ReactNode;
  submit: (data: FormData) => Promise<void>;
  success: string;
  className?: string;
}) {
  const [working, setWorking] = useState(false);
  const [error, setError] = useState("");
  const [saved, setSaved] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const data = new FormData(event.currentTarget);
    setWorking(true);
    setError("");
    setSaved(false);
    try {
      await submit(data);
      setSaved(true);
    } catch (problem) {
      setError(errorMessage(problem));
    } finally {
      setWorking(false);
    }
  }

  return (
    <form className={className} onSubmit={(event) => void handleSubmit(event)}>
      <fieldset disabled={working}>{children}</fieldset>
      {working && <p role="status">Guardando…</p>}
      {error && <p className="error" role="alert">{error}</p>}
      {saved && <p role="status">{success}</p>}
    </form>
  );
}

export function FormButton({ children }: { children: ReactNode }) {
  return <button className="button" type="submit">{children}</button>;
}
