import type { ReactNode } from "react";
import Storefront from "./storefront";

export default function CustomerLayout({ children }: { children: ReactNode }) {
  return <><Storefront />{children}</>;
}
