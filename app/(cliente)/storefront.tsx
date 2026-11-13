"use client";

import Link from "next/link";
import Image from "next/image";
import { usePathname, useRouter, useSearchParams } from "next/navigation";
import { Suspense, useCallback, useEffect, useRef, useState, type FormEvent } from "react";
import { useSession } from "../session";
import FeaturedCarousel from "../featured-carousel";

type Business = {
  id: string;
  name: string;
  sector: string;
  address: string | null;
  offers_pickup: boolean;
  offers_delivery: boolean;
  accepting_orders: boolean;
  delivery_fee: number | null;
};

type Offer = {
  id: string;
  business_id: string;
  name: string;
  category: string;
  brand: string | null;
  price: number;
  original_price: number | null;
  kind: string;
  variant_id: string | null;
  components?: { name: string; quantity: number }[];
};

type Catalog = { businesses: Business[]; offers: Offer[] };
type CartLine = { offer: Offer; business: Business; quantity: number };
type Location = { latitude: number; longitude: number };
type Fulfillment = { mode: "pickup" | "delivery"; address?: string } & Partial<Location>;
type Quote = {
  quoteToken: string;
  total: number | null;
  productsTotal: number;
  orders: {
    business_id: string;
    name: string;
    subtotal: number;
    delivery_fee: number | null;
    total: number | null;
    items: { offer_id: string; name: string; price: number; quantity: number }[];
  }[];
};
type History = {
  id: string;
  group_id?: string;
  created_at?: string;
  business_id: string;
  business_name?: string;
  status: string;
  version: number;
  subtotal: number;
  delivery_fee: number | null;
  total: number | null;
  mode: "pickup" | "delivery";
  address?: string | null;
  pickup_address?: string | null;
  reason?: string | null;
  items: { offer_id: string; name: string; quantity: number; total: number }[];
  proposal?: {
    mode: "pickup" | "delivery";
    address: string | null;
    delivery_fee: number | null;
    window: string | null;
    version: number;
  } | null;
};

const currency = new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" });
const storageKey = "dondepido-cart-v1";
const maxQuantity = 20;
const formatMoney = (cents: number) => currency.format(cents / 100);
const formatDeliveryFee = (cents: number | null) =>
  typeof cents === "number" ? `Costo de entrega: ${formatMoney(cents)}` : "Costo de entrega a coordinar.";

class MarketError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
  }
}

async function request<T>(input: object, accessToken?: string, signal?: AbortSignal): Promise<T> {
  const response = await fetch("/api/market", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: JSON.stringify(input),
    signal,
  });
  const result = await response.json();
  if (!response.ok || result.error) {
    const message = typeof result.error === "string" ? result.error : result.error?.message;
    throw new MarketError(message || "No pudimos completar la operación. Intentá de nuevo.", response.status);
  }
  return result.data;
}

const statusNames: Record<string, string> = {
  received: "Pendiente del comercio",
  confirmed: "Confirmado",
  rejected: "Rechazado",
  cancelled: "Cancelado",
  completed: "Completado",
  expired: "Vencido",
};
const sectorNames: Record<string, string> = { gastronomia: "Gastronomía", kioscos: "Kioscos" };

const destinations: Partial<Record<string, "explorar" | "carrito" | "pedidos">> = {
  "/explorar": "explorar",
  "/carrito": "carrito",
  "/pedidos": "pedidos",
};
type ExploreRoute = { sector: string; businessId: string };

function clearExploreRoute() {
  if (window.location.search) window.history.replaceState(null, "", "/explorar");
}

function ExploreRouteSync({ onRoute }: { onRoute: (route: ExploreRoute) => void }) {
  const pathname = usePathname();
  const search = useSearchParams();
  const sector = search.get("rubro") ?? "";
  const businessId = search.get("comercio") ?? "";
  useEffect(() => {
    if (pathname === "/explorar" && (sector || businessId)) onRoute({ sector, businessId });
  }, [pathname, sector, businessId, onRoute]);
  return null;
}

export default function Storefront() {
  const pathname = usePathname();
  const router = useRouter();
  const activePage = destinations[pathname] ?? "inicio";
  const accountHref = `/cuenta?next=${encodeURIComponent(pathname)}`;
  const { session, ready } = useSession();
  const accessToken = session && !session.recovery ? session.access_token : undefined;
  const [q, setQ] = useState("");
  const [query, setQuery] = useState({ q: "", sector: "", category: "", businessId: "", promotions: false, attempt: 0 });
  const [catalog, setCatalog] = useState<Catalog>({ businesses: [], offers: [] });
  const [facets, setFacets] = useState({ sectors: [] as string[], categories: [] as string[] });
  const [catalogLoading, setCatalogLoading] = useState(true);
  const [catalogError, setCatalogError] = useState("");
  const [cart, setCart] = useState<CartLine[]>([]);
  const [cartLoaded, setCartLoaded] = useState(false);
  const [fulfillment, setFulfillment] = useState<Record<string, Fulfillment>>({});
  const [locationMessage, setLocationMessage] = useState<Record<string, string>>({});
  const [quote, setQuote] = useState<Quote | null>(null);
  const [idempotencyKey, setIdempotencyKey] = useState("");
  const [busy, setBusy] = useState(false);
  const [submitUncertain, setSubmitUncertain] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [history, setHistory] = useState<History[]>([]);
  const [historyError, setHistoryError] = useState("");
  const [historyLoading, setHistoryLoading] = useState(false);
  const [historyRevision, setHistoryRevision] = useState(0);
  const [historyAction, setHistoryAction] = useState({ busy: false, message: "", error: "" });
  const updatingHistory = useRef(false);
  const [businessFilter, setBusinessFilter] = useState("");
  const [variantFilter, setVariantFilter] = useState("");
  const [consentBusy, setConsentBusy] = useState(false);
  const [consentMessage, setConsentMessage] = useState("");
  const [consentError, setConsentError] = useState("");
  const editingLocked = busy || submitUncertain;
  const submitting = useRef(false);
  const browseSeed = useRef("");
  const cartCount = cart.reduce((sum, line) => sum + line.quantity, 0);
  const cartTotal = cart.reduce((sum, line) => sum + line.offer.price * line.quantity, 0);
  const groupedCart = new Map<string, CartLine[]>();
  for (const line of cart) {
    const current = groupedCart.get(line.business.id) ?? [];
    current.push(line);
    groupedCart.set(line.business.id, current);
  }
  const businessGroups = [...groupedCart.values()];
  const historyGroups = new Map<string, History[]>();
  for (const order of history) {
    const key = order.group_id ?? order.id;
    const orders = historyGroups.get(key) ?? [];
    orders.push(order);
    historyGroups.set(key, orders);
  }

  useEffect(() => {
    try {
      const saved = JSON.parse(localStorage.getItem(storageKey) ?? "[]");
      if (Array.isArray(saved)) setCart(saved);
    } catch {
      // The storefront still works with an empty cart when storage is unavailable.
    }
    setCartLoaded(true);
  }, []);

  useEffect(() => {
    if (!cartLoaded) return;
    try {
      localStorage.setItem(storageKey, JSON.stringify(cart));
    } catch {
      // Keep the current cart available in memory.
    }
  }, [cart, cartLoaded]);

  useEffect(() => {
    if (pathname !== "/") return;
    const redirectLegacySection = () => {
      const section = window.location.hash.slice(1);
      if (section === "explorar" || section === "carrito" || section === "pedidos") router.replace(`/${section}`);
    };
    redirectLegacySection();
    window.addEventListener("hashchange", redirectLegacySection);
    return () => window.removeEventListener("hashchange", redirectLegacySection);
  }, [pathname, router]);

  useEffect(() => {
    if (activePage !== "explorar") return;
    const controller = new AbortController();
    browseSeed.current ||= crypto.randomUUID();
    setCatalogLoading(true);
    setCatalogError("");
    const term = query.promotions ? `promos ${query.q}`.trim() : query.q;
    request<Catalog>({ action: "browse", seed: browseSeed.current, q: term, sector: query.sector, category: query.category, businessId: query.businessId || undefined }, undefined, controller.signal)
      .then((result) => {
        setCatalog(result);
        if (!query.q && !query.sector && !query.category && !query.businessId && !query.promotions) {
          setFacets({
            sectors: [...new Set(result.businesses.map((item) => item.sector))].filter(Boolean).sort(),
            categories: [...new Set(result.offers.map((item) => item.category))].filter(Boolean).sort(),
          });
        }
      })
      .catch((problem: Error) => {
        if (!controller.signal.aborted) setCatalogError(problem.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setCatalogLoading(false);
      });
    return () => controller.abort();
  }, [query, activePage]);

  useEffect(() => {
    if (!accessToken || activePage !== "pedidos") return;
    const controller = new AbortController();
    setHistory([]);
    setHistoryError("");
    setHistoryLoading(true);
    request<{ orders: History[] }>({ action: "orders", operation: "mine" }, accessToken, controller.signal)
      .then(({ orders }) => setHistory(orders))
      .catch((problem: Error) => {
        if (!controller.signal.aborted) setHistoryError(problem.message);
      })
      .finally(() => {
        if (!controller.signal.aborted) setHistoryLoading(false);
      });
    return () => controller.abort();
  }, [accessToken, historyRevision, activePage]);

  function resetReview() {
    setQuote(null);
    setIdempotencyKey("");
    setSubmitUncertain(false);
    setError("");
    setMessage("");
  }

  function changeQuantity(offer: Offer, business: Business, delta: number) {
    if (editingLocked) return;
    resetReview();
    setCart((lines) => {
      const line = lines.find((entry) => entry.offer.id === offer.id);
      if (!line) {
        return delta > 0 ? [...lines, { offer, business, quantity: delta }] : lines;
      }
      const quantity = Math.min(maxQuantity, line.quantity + delta);
      return lines.flatMap((entry) => entry !== line ? [entry] : quantity > 0 ? [{ ...entry, quantity }] : []);
    });
  }

  function updateFulfillment(businessId: string, changes: Fulfillment) {
    resetReview();
    setFulfillment((current) => ({ ...current, [businessId]: changes }));
  }

  function locate(businessId: string) {
    if (!navigator.geolocation) {
      setLocationMessage((current) => ({ ...current, [businessId]: "La ubicación no está disponible. Podés ingresar la dirección manualmente." }));
      return;
    }
    setLocationMessage((current) => ({ ...current, [businessId]: "Obteniendo ubicación…" }));
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => {
        if (submitting.current) {
          setLocationMessage((current) => ({ ...current, [businessId]: "Volvé a pedir la ubicación si querés compartirla." }));
          return;
        }
        setFulfillment((current) => {
          const selected = current[businessId];
          if (selected?.mode !== "delivery") return current;
          return { ...current, [businessId]: { ...selected, latitude: coords.latitude, longitude: coords.longitude } };
        });
        resetReview();
        setLocationMessage((current) => ({ ...current, [businessId]: "Ubicación obtenida. Revisá también la dirección escrita." }));
      },
      () => setLocationMessage((current) => ({ ...current, [businessId]: "No pudimos obtener la ubicación. Podés ingresar la dirección manualmente." })),
      { timeout: 8000, maximumAge: 0 },
    );
  }

  function selectedMode(business: Business): Fulfillment {
    return fulfillment[business.id] ?? { mode: business.offers_pickup ? "pickup" : "delivery" };
  }

  async function checkout(event: FormEvent) {
    event.preventDefault();
    if (!accessToken || !cart.length || submitting.current) return;
    const items = cart.map(({ offer, quantity }) => ({ offerId: offer.id, quantity }));
    const deliveryChoices = businessGroups.map((lines) => {
      const { business } = lines[0];
      return { businessId: business.id, ...selectedMode(business) };
    });
    if (deliveryChoices.some((item) => item.mode === "delivery" && !item.address?.trim())) {
      setError("Completá la dirección de cada comercio con entrega.");
      return;
    }
    submitting.current = true;
    setBusy(true);
    setError("");
    setMessage("");
    try {
      if (!quote) {
        const result = await request<Quote>({ action: "orders", operation: "quote", items, fulfillment: deliveryChoices }, accessToken);
        if (!result.quoteToken) throw new Error("No pudimos verificar la cotización.");
        setQuote(result);
        setIdempotencyKey(crypto.randomUUID());
        setMessage("Revisá el importe y confirmá el envío a los comercios.");
      } else {
        await request({ action: "orders", operation: "submit", quoteToken: quote.quoteToken, idempotencyKey }, accessToken);
        setCart([]);
        setFulfillment({});
        setLocationMessage({});
        resetReview();
        setHistoryRevision((previous) => previous + 1);
        setMessage("Solicitudes enviadas. Cada comercio tiene que confirmar su parte.");
      }
    } catch (problem) {
      setError(problem instanceof Error ? problem.message : "No pudimos completar la operación.");
      if (quote) {
        const uncertain = !(problem instanceof MarketError) || problem.status >= 500 || submitUncertain;
        setSubmitUncertain(uncertain);
        if (!uncertain) {
          setQuote(null);
          setIdempotencyKey("");
        }
      }
    } finally {
      submitting.current = false;
      setBusy(false);
    }
  }

  function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    clearExploreRoute();
    setBusinessFilter("");
    setVariantFilter("");
    setQuery((previous) => ({ ...previous, q: q.trim(), businessId: "", attempt: previous.attempt + 1 }));
  }

  const openExploreRoute = useCallback(({ sector, businessId }: ExploreRoute) => {
    setQ("");
    setBusinessFilter(businessId);
    setVariantFilter("");
    setQuery((previous) => ({ q: "", sector, category: "", businessId, promotions: false, attempt: previous.attempt + 1 }));
  }, []);

  async function updateConsent(enabled: boolean) {
    if (!accessToken || consentBusy) return;
    setConsentBusy(true);
    setConsentMessage("");
    setConsentError("");
    try {
      await request({ action: "orders", operation: "consent", enabled }, accessToken);
      setConsentMessage(enabled ? "Preferencia guardada. Aceptaste las notificaciones por WhatsApp." : "Preferencia guardada. Desactivaste las notificaciones por WhatsApp.");
    } catch (problem) {
      setConsentError(problem instanceof Error ? problem.message : "No pudimos guardar la preferencia.");
    } finally {
      setConsentBusy(false);
    }
  }

  async function updateOrder(order: History, operation: "cancel" | "respond", changes: object, successMessage: string) {
    if (!accessToken || updatingHistory.current) return;
    updatingHistory.current = true;
    setHistoryAction({ busy: true, message: "", error: "" });
    try {
      await request({ action: "orders", operation, orderId: order.id, expectedVersion: order.version, ...changes }, accessToken);
      setHistoryAction({ busy: false, message: successMessage, error: "" });
      setHistoryRevision((previous) => previous + 1);
    } catch (problem) {
      setHistoryAction({ busy: false, message: "", error: problem instanceof Error ? problem.message : "No pudimos actualizar el pedido." });
      if (problem instanceof MarketError && problem.status === 409) setHistoryRevision((previous) => previous + 1);
    } finally {
      updatingHistory.current = false;
    }
  }

  const visibleOffers = catalog.offers
    .filter((offer) => (!businessFilter || offer.business_id === businessFilter) && (!variantFilter || offer.variant_id === variantFilter))
    .sort((first, second) => variantFilter ? first.price - second.price : 0);

  return (
    <>
      <Suspense fallback={null}><ExploreRouteSync onRoute={openExploreRoute} /></Suspense>
      <a className="skip-link" href="#principal">Ir al contenido</a>
      <header className="market-header">
        <nav className="shell market-nav" aria-label="Navegación principal">
          <Link href="/" className="brand" aria-label="DondePido, inicio"><Image src="/brand/dondepido.png" alt="DondePido." width={96} height={58} priority /></Link>
          <div className="market-nav-links">
            <Link href="/explorar" aria-current={activePage === "explorar" ? "page" : undefined}>Explorar</Link>
            <Link href="/pedidos" aria-current={activePage === "pedidos" ? "page" : undefined}>Mis pedidos</Link>
            <Link href="/gestion">Soy comercio</Link>
            <Link href={accountHref}>{ready && session ? "Mi cuenta" : "Ingresar"}</Link>
            <Link className="market-cart-link" href="/carrito" aria-current={activePage === "carrito" ? "page" : undefined}>Carrito <span>{cartCount}</span></Link>
          </div>
        </nav>
      </header>
      <main id="principal" className="shell market-main">
        {activePage === "inicio" && <>
        <section className="market-hero" aria-labelledby="hero-title">
          <div className="market-hero-content">
            <h1 id="hero-title">Encontrá, compará y pedí.</h1>
            <p>Descubrí qué ofrecen los comercios de Deán Funes y armá tu pedido desde un mismo lugar.</p>
            <div className="market-hero-actions">
              <Link className="button accent" href="/explorar?rubro=gastronomia">Gastronomía</Link>
              <Link className="button hero-secondary" href="/explorar?rubro=kioscos">Kioscos</Link>
            </div>
          </div>
        </section>
        <FeaturedCarousel />
        </>}
        {activePage === "explorar" && <section id="explorar" className="market-section market-screen" aria-labelledby="explore-title">
          <div className="market-section-heading">
            <h1 id="explore-title">Explorá productos y comercios</h1>
          </div>
          <form className="market-search panel" onSubmit={search}>
            <label>Buscar
              <input className="field" type="search" value={q} maxLength={180} onChange={(event) => setQ(event.target.value)} placeholder="Ej. Coca-Cola, lomitos o tu comercio" />
            </label>
            <label>Rubro
              <select className="field" value={query.sector} onChange={(event) => {
                clearExploreRoute();
                setBusinessFilter("");
                setVariantFilter("");
                setQuery((previous) => ({ ...previous, sector: event.target.value, businessId: "" }));
              }}>
                <option value="">Todos</option>
                {[...new Set([...Object.keys(sectorNames), ...facets.sectors])].map((sector) => <option key={sector} value={sector}>{sectorNames[sector] ?? sector}</option>)}
              </select>
            </label>
            <label>Categoría
              <select className="field" value={query.category} onChange={(event) => {
                clearExploreRoute();
                setBusinessFilter("");
                setVariantFilter("");
                setQuery((previous) => ({ ...previous, category: event.target.value, businessId: "" }));
              }}>
                <option value="">Todas</option>
                {facets.categories.map((category) => <option key={category}>{category}</option>)}
              </select>
            </label>
            <button className="button" type="submit">Buscar</button>
          </form>
          <div className="market-filters">
            <label><input type="checkbox" checked={query.promotions} onChange={(event) => {
              clearExploreRoute();
              setBusinessFilter("");
              setVariantFilter("");
              setQuery((previous) => ({ ...previous, promotions: event.target.checked, businessId: "" }));
            }} /> Solo promociones</label>
          </div>
          {catalogLoading ? <p role="status">Cargando catálogo…</p> : catalogError ? (
            <div role="alert" className="panel error">
              <p>{catalogError}</p>
              <button className="button secondary" onClick={() => setQuery((previous) => ({ ...previous, attempt: previous.attempt + 1 }))}>Reintentar</button>
            </div>
          ) : (
            <>
              {catalog.businesses.length > 0 && (
                <div className="market-stores" aria-label="Filtrar por comercio">
                  <button className="button secondary" aria-pressed={!businessFilter} onClick={() => {
                    clearExploreRoute();
                    setBusinessFilter("");
                    if (query.businessId) setQuery((previous) => ({ ...previous, businessId: "" }));
                  }}>Todos los comercios</button>
                  {catalog.businesses.map((business) => (
                    <Link
                      key={business.id}
                      className="button secondary"
                      aria-current={businessFilter === business.id ? "location" : undefined}
                      href={{ pathname: "/explorar", query: { rubro: business.sector, comercio: business.id } }}
                    >{business.name}</Link>
                  ))}
                </div>
              )}
              {variantFilter && <p className="market-feedback">Misma presentación, ordenada por precio. <button className="button secondary" onClick={() => setVariantFilter("")}>Quitar comparación</button></p>}
              {businessFilter && catalog.businesses.filter((business) => business.id === businessFilter).map((business) => (
                <article className="panel market-business" key={business.id}>
                  <h3>{business.name}</h3>
                  <p>{[sectorNames[business.sector] ?? business.sector, business.address].filter(Boolean).join(" · ")}</p>
                  <p>{[business.offers_pickup && "Retiro", business.offers_delivery && "Entrega"].filter(Boolean).join(" · ")}</p>
                </article>
              ))}
              {!visibleOffers.length && <p className="panel muted">No encontramos ofertas con esos filtros.</p>}
              <div className="market-grid">
                {visibleOffers.map((offer) => {
                  const business = catalog.businesses.find((item) => item.id === offer.business_id);
                  if (!business) return null;
                  return (
                    <article className="market-offer panel" key={offer.id}>
                      <div className="market-offer-meta">
                        <span>{offer.category}</span>
                        {(offer.kind === "combo" || (offer.original_price !== null && offer.original_price > offer.price)) && (
                          <span className="market-badge">{offer.kind === "combo" ? "Combo" : "Rebaja"}</span>
                        )}
                      </div>
                      <h3>{offer.name}</h3>
                      <p className="muted">{[offer.brand, business.name].filter(Boolean).join(" · ")}</p>
                      {offer.kind === "combo" && !!offer.components?.length && (
                        <p className="muted">{offer.components.map((item) => `${item.quantity} × ${item.name}`).join(" · ")}</p>
                      )}
                      {!business.accepting_orders && <p className="muted">Por ahora no recibe pedidos.</p>}
                      <div className="market-offer-bottom">
                        <div className="market-offer-price">
                          {offer.original_price !== null && offer.original_price > offer.price && <del>{formatMoney(offer.original_price)}</del>}
                          <strong>{formatMoney(offer.price)}</strong>
                        </div>
                        <button className="button secondary" disabled={editingLocked || !business.accepting_orders} onClick={() => changeQuantity(offer, business, 1)} aria-label={`Agregar ${offer.name} de ${business.name}`}>Agregar</button>
                      </div>
                      {!variantFilter && offer.variant_id && catalog.offers.some((other) => other.variant_id === offer.variant_id && other.business_id !== offer.business_id) && (
                        <button className="button secondary" onClick={() => {
                          clearExploreRoute();
                          setBusinessFilter("");
                          if (query.businessId) setQuery((previous) => ({ ...previous, businessId: "" }));
                          setVariantFilter(offer.variant_id ?? "");
                        }}>Comparar misma presentación</button>
                      )}
                    </article>
                  );
                })}
              </div>
            </>
          )}
        </section>}
        {activePage === "carrito" && <section id="carrito" className="market-section market-screen" aria-labelledby="cart-title">
          <div className="market-section-heading"><h1 id="cart-title">Tu carrito</h1><span className="muted">{cartCount} {cartCount === 1 ? "unidad" : "unidades"}</span></div>
          {message && <p role="status" className="market-feedback">{message}{!cart.length && <> <Link href="/pedidos">Ver mis pedidos</Link></>}</p>}
          {error && <p role="alert" className="market-feedback error">{error}</p>}
          {!cart.length ? <div className="panel"><p className="muted">Agregá productos para armar tu pedido.</p><Link href="/explorar">Explorar productos</Link></div> : (
            <form className="market-checkout" onSubmit={checkout}>
              <div className="market-cart-groups">
                {businessGroups.map((lines) => {
                  const { business } = lines[0];
                  const selected = selectedMode(business);
                  const quoted = quote?.orders.find((item) => item.business_id === business.id);
                  const subtotal = lines.reduce((sum, line) => sum + line.offer.price * line.quantity, 0);
                  return (
                    <article key={business.id} className="panel market-cart-group">
                      <h3>{business.name}</h3>
                      <ul>
                        {lines.map(({ offer, quantity }) => {
                          const currentPrice = quoted?.items.find((item) => item.offer_id === offer.id)?.price;
                          return (
                          <li key={offer.id} className="market-cart-line">
                            <div>
                              <strong>{offer.name}</strong><br />
                              <span className="muted">{formatMoney(currentPrice ?? offer.price)} por unidad</span>
                              {currentPrice !== undefined && currentPrice !== offer.price && <p>Precio actualizado. Antes {formatMoney(offer.price)}.</p>}
                            </div>
                            <div className="market-stepper">
                              <button type="button" disabled={editingLocked} onClick={() => changeQuantity(offer, business, -1)} aria-label={`Quitar una unidad de ${offer.name}`}>−</button>
                              <output aria-label={`Cantidad de ${offer.name}`}>{quantity}</output>
                              <button type="button" disabled={editingLocked || quantity >= maxQuantity} onClick={() => changeQuantity(offer, business, 1)} aria-label={`Sumar una unidad de ${offer.name}`}>+</button>
                            </div>
                          </li>
                          );
                        })}
                      </ul>
                      <p className="market-subtotal"><span>Subtotal de productos</span><strong>{formatMoney(quoted?.subtotal ?? subtotal)}</strong></p>
                      <label>Modalidad
                        <select className="field" disabled={editingLocked} value={selected.mode} onChange={(event) => {
                          setLocationMessage((current) => ({ ...current, [business.id]: "" }));
                          updateFulfillment(business.id, { mode: event.target.value === "delivery" ? "delivery" : "pickup" });
                        }}>
                          {business.offers_pickup && <option value="pickup">Retiro en el comercio</option>}
                          {business.offers_delivery && <option value="delivery">Entrega a coordinar</option>}
                        </select>
                      </label>
                      {selected.mode === "delivery" && (
                        <div className="market-address">
                          <p className="muted">{formatDeliveryFee(quoted ? quoted.delivery_fee : business.delivery_fee)}</p>
                          <label>Dirección de entrega
                            <input className="field" disabled={editingLocked} required maxLength={250} value={selected.address ?? ""} onChange={(event) => updateFulfillment(business.id, { ...selected, address: event.target.value })} placeholder="Calle, altura y localidad" />
                          </label>
                          {selected.latitude !== undefined ? (
                            <button type="button" className="button secondary" disabled={editingLocked} onClick={() => {
                              updateFulfillment(business.id, { mode: "delivery", address: selected.address });
                              setLocationMessage((current) => ({ ...current, [business.id]: "" }));
                            }}>Quitar ubicación</button>
                          ) : (
                            <button type="button" className="button secondary" disabled={editingLocked || locationMessage[business.id] === "Obteniendo ubicación…"} onClick={() => {
                              setFulfillment((current) => ({ ...current, [business.id]: selected }));
                              locate(business.id);
                            }}>Compartir mi ubicación (opcional)</button>
                          )}
                          {locationMessage[business.id] && <p className="muted" role="status">{locationMessage[business.id]}</p>}
                        </div>
                      )}
                    </article>
                  );
                })}
              </div>
              <aside className="panel market-summary" aria-label="Resumen del carrito">
                <h3>Resumen</h3>
                <p className="market-subtotal"><span>Total de productos</span><strong>{formatMoney(quote?.productsTotal ?? cartTotal)}</strong></p>
                {quote && <p className="market-subtotal"><span>Total con entrega</span><strong>{quote.total === null ? "A coordinar" : formatMoney(quote.total)}</strong></p>}
                <p className="muted">Cada comercio confirma su pedido y coordina el pago y la entrega con vos. Los cargos de entrega a coordinar se acuerdan directamente.</p>
                {!ready ? <p role="status">Comprobando sesión…</p> : !accessToken ? (
                  <Link className="button" href={accountHref}>{session?.recovery ? "Completá la recuperación de tu cuenta" : "Ingresá para pedir"}</Link>
                ) : (
                  <>
                    <Link href="/cuenta?vista=telefono&next=%2Fcarrito">Verificar mi teléfono</Link>
                    <button className="button" disabled={busy} type="submit">{busy ? "Procesando…" : submitUncertain ? "Reintentar el mismo envío" : quote ? "Enviar solicitudes" : "Revisar pedido"}</button>
                  </>
                )}
              </aside>
            </form>
          )}
        </section>}
        {activePage === "pedidos" && <section id="pedidos" className="market-section market-screen" aria-labelledby="history-title">
          <div className="market-section-heading">
            <h1 id="history-title">Mis pedidos</h1>
            {accessToken && <button className="button secondary" disabled={historyLoading} onClick={() => setHistoryRevision((previous) => previous + 1)}>Actualizar</button>}
          </div>
          {accessToken && historyAction.message && <p className="market-feedback" role="status">{historyAction.message}</p>}
          {accessToken && historyAction.error && <p className="market-feedback error" role="alert">{historyAction.error}</p>}
          {!ready ? <p role="status">Comprobando sesión…</p> : !accessToken ? (
            <div className="panel"><p>{session?.recovery ? "Completá la recuperación para consultar tus pedidos." : "Ingresá para consultar tus pedidos y sus estados."}</p><Link href={accountHref}>Ir a mi cuenta</Link></div>
          ) : historyLoading ? <p role="status">Cargando pedidos…</p> : historyError ? (
            <p className="panel error" role="alert">{historyError}</p>
          ) : !history.length ? <p className="panel muted">Todavía no tenés pedidos.</p> : (
            <div className="market-history">
              {[...historyGroups].map(([groupId, orders]) => (
                <article key={groupId} className="panel">
                  <h3>Pedido {groupId.slice(0, 8)}</h3>
                  {orders[0].created_at && <p className="muted">{new Date(orders[0].created_at).toLocaleString("es-AR")}</p>}
                  <ul>
                    {orders.map((order) => (
                      <li key={order.id}>
                        <details>
                          <summary><strong>{order.business_name ?? "Comercio"}</strong> · {statusNames[order.status] ?? order.status}</summary>
                          <p>{order.mode === "pickup" ? "Retiro" : "Entrega"} · {order.mode === "pickup" ? order.pickup_address : order.address}</p>
                          {!!order.items.length && <ul>{order.items.map((item) => <li key={item.offer_id}>{item.quantity} × {item.name} · {formatMoney(item.total)}</li>)}</ul>}
                          <p>Productos: {formatMoney(order.subtotal)}</p>
                          {order.mode === "delivery" && <p>{formatDeliveryFee(order.delivery_fee)}</p>}
                          {order.reason && <p>{order.reason}</p>}
                          {order.status === "received" && order.proposal && (
                            <div className="market-order-proposal">
                              <h4>Cambios propuestos por el comercio</h4>
                              <p>{order.proposal.mode === "pickup" ? "Retiro" : "Entrega"}{order.proposal.address ? ` · ${order.proposal.address}` : ""}</p>
                              {order.proposal.mode === "delivery" && <p>{formatDeliveryFee(order.proposal.delivery_fee)}</p>}
                              {typeof order.proposal.window === "string" && order.proposal.window && <p>Horario propuesto: {order.proposal.window}</p>}
                              <div className="market-order-actions">
                                <button className="button" type="button" disabled={historyAction.busy} onClick={() => {
                                  void updateOrder(order, "respond", { accept: true }, "Cambios aceptados. El comercio todavía tiene que confirmar el pedido.");
                                }}>Aceptar cambios</button>
                                <button className="button secondary" type="button" disabled={historyAction.busy} onClick={() => {
                                  void updateOrder(order, "respond", { accept: false }, "Cambios rechazados.");
                                }}>Rechazar cambios</button>
                              </div>
                            </div>
                          )}
                          {order.status === "received" && (
                            <div className="market-order-actions">
                              <button className="button secondary" type="button" disabled={historyAction.busy} onClick={() => {
                                if (window.confirm(`¿Querés cancelar el pedido de ${order.business_name ?? "este comercio"}?`)) {
                                  void updateOrder(order, "cancel", {}, "Pedido cancelado.");
                                }
                              }}>Cancelar pedido</button>
                            </div>
                          )}
                        </details>
                      </li>
                    ))}
                  </ul>
                </article>
              ))}
            </div>
          )}
          {accessToken && (
            <details className="panel market-preferences">
              <summary>Preferencia de WhatsApp</summary>
              <p className="muted">Podés elegir si querés recibir avisos de pedidos cuando este canal esté habilitado.</p>
              <div className="market-preference-actions">
                <button className="button secondary" disabled={consentBusy} onClick={() => updateConsent(true)}>Aceptar avisos</button>
                <button className="button secondary" disabled={consentBusy} onClick={() => updateConsent(false)}>Desactivar avisos</button>
              </div>
              {consentMessage && <p role="status">{consentMessage}</p>}
              {consentError && <p role="alert" className="error">{consentError}</p>}
            </details>
          )}
        </section>}
      </main>
      <footer className="market-footer"><div className="shell"><span>DondePido.</span><Link href="/gestion">Acceso para comercios</Link></div></footer>
    </>
  );
}
