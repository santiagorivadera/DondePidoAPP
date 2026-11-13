import type { Metadata } from "next";
import type { ReactNode } from "react";
import { SessionProvider } from "./session";
import "./globals.css";

export const metadata: Metadata = {
  title: "DondePido. | Encontrá, compará y pedí",
  description: "Compará productos y promociones de comercios locales y pedí desde un mismo lugar.",
  icons: { icon: "/brand/dondepido.png" },
};

export default function RootLayout({ children }: { children: ReactNode }) {
  return (
    <html lang="es-AR">
      <body><SessionProvider>{children}</SessionProvider></body>
    </html>
  );
}
