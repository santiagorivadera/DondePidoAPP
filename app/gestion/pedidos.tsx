"use client";

import { useEffect, useState } from "react";
import { errorMessage, requestApi } from "../session";
import { amountInMinor, formatPrice } from "./catalogo";
import { ActionForm, FormButton, valueOf } from "./forms";

type OrderLine = {
  offer_id: string;
  name: string;
  quantity: number;
};
type Order = {
  id: string;
  status: string;
  version: number;
  subtotal: number;
  mode: "delivery" | "pickup";
  address: string | null;
  pickup_address: string | null;
  customer_phone?: string | null;
  delivery_fee: number | null;
  reason: string | null;
  window: string | null;
  proposal: { status?: string; mode?: string; address?: string | null; delivery_fee?: number | null; window?: string | null } | null;
  items: OrderLine[];
  created_at: string;
};
type HistoricalStatus = "received" | "confirmed" | "rejected" | "completed" | "cancelled" | "expired";
type Peak = { label: string; count: number };
type OrderStats = {
  timeZone: string;
  counts: Record<HistoricalStatus, number>;
  peakMonth: Peak | null;
  peakWeekday: Peak | null;
  peakHour: Peak | null;
};

const states: Record<string, string> = {
  received: "Recibido", confirmed: "Confirmado", rejected: "Rechazado", completed: "Completado",
  cancelled: "Cancelado", canceled: "Cancelado", expired: "Vencido",
};
const historicalLabels: Record<HistoricalStatus, string> = {
  received: "Recibidos", confirmed: "Confirmados", rejected: "Rechazados", completed: "Completados",
  cancelled: "Cancelados", expired: "Vencidos",
};
const weekdays = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"];
const monthFormat = new Intl.DateTimeFormat("es-AR", { month: "long", year: "numeric", timeZone: "UTC" });

function stateOf(order: Order) {
  const state = order.status.toLowerCase();
  return state === "canceled" ? "cancelled" : state;
}

export function OrdersPanel({ businessId, token }: { businessId: string; token: string }) {
  const [orders, setOrders] = useState<Order[] | null>(null);
  const [error, setError] = useState("");
  const [filter, setFilter] = useState("");
  const [revision, setRevision] = useState(0);
  const refresh = () => setRevision((version) => version + 1);

  useEffect(() => {
    let active = true;
    void requestApi<{ orders: Order[] }>("market", { action: "orders", operation: "inbox", businessId }, token).then(
      (data) => { if (active) { setOrders(data.orders); setError(""); } },
      (problem) => { if (active) setError(errorMessage(problem)); },
    );
    return () => { active = false; };
  }, [businessId, token, revision]);

  const visible = orders?.filter((order) => !filter || stateOf(order) === filter);
  return (
    <section className="panel" aria-labelledby="orders-heading">
      <h2 id="orders-heading">Pedidos</h2>
      <div className="gestion-fields">
        <label className="field">Estado<select value={filter} onChange={(event) => setFilter(event.target.value)}>
          <option value="">Todos</option>
          {Object.entries(states).filter(([state]) => state !== "canceled").map(([state, label]) => (
            <option key={state} value={state}>{label}</option>
          ))}
        </select></label>
        <button type="button" className="button secondary" onClick={refresh}>Actualizar pedidos</button>
      </div>
      {error && <p className="error" role="alert">{error}</p>}
      {!orders && !error && <p role="status">Cargando pedidos…</p>}
      {visible?.length === 0 && <p>No hay pedidos para mostrar.</p>}
      {visible?.map((order) => <OrderCard key={order.id} order={order} token={token} refresh={refresh} />)}
    </section>
  );
}

export function IndicatorsPanel({ businessId, token }: { businessId: string; token: string }) {
  const [stats, setStats] = useState<OrderStats | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);

  useEffect(() => {
    let active = true;
    void requestApi<OrderStats>("market", { action: "orders", operation: "stats", businessId }, token).then(
      (data) => { if (active) { setStats(data); setError(""); } },
      (problem) => { if (active) { setStats(null); setError(errorMessage(problem)); } },
    );
    return () => { active = false; };
  }, [businessId, token, revision]);

  return (
    <section className="panel" aria-labelledby="historical-stats-heading">
      <h2 id="historical-stats-heading">Indicadores históricos</h2>
      <button type="button" className="button secondary" onClick={() => {
        setStats(null);
        setError("");
        setRevision((current) => current + 1);
      }}>Actualizar indicadores</button>
      {!stats && !error && <p role="status">Cargando indicadores…</p>}
      {error && <p role="alert" className="error">No pudimos cargar los indicadores. {error}</p>}
      {stats && (
        <>
          <p className="muted">Eventos desde el inicio. Un pedido puede contar en más de un estado.</p>
          <dl className="gestion-counts">
            {(Object.keys(historicalLabels) as HistoricalStatus[]).map((status) => (
              <div key={status}>
                <dt>{historicalLabels[status]}</dt>
                <dd>{stats.counts[status].toLocaleString("es-AR")}</dd>
              </div>
            ))}
          </dl>
          <h3>Mayor actividad en pedidos completados</h3>
          <p className="muted">Un pedido completado registra un retiro o una entrega. Los cobros se coordinan por fuera.</p>
          {stats.peakMonth || stats.peakWeekday || stats.peakHour ? (
            <dl className="gestion-counts">
              <PeakValue title="Mes" peak={stats.peakMonth} formatLabel={(label) => monthFormat.format(new Date(`${label}-01T00:00:00Z`))} />
              <PeakValue title="Día de la semana" peak={stats.peakWeekday} formatLabel={(label) => weekdays[Number(label) - 1] ?? label} />
              <PeakValue title="Hora" peak={stats.peakHour} formatLabel={(label) => `${label.padStart(2, "0")}:00`} />
            </dl>
          ) : <p>Todavía no hay pedidos completados.</p>}
          <p className="muted">Hora local · {stats.timeZone}</p>
        </>
      )}
    </section>
  );
}

function PeakValue({ title, peak, formatLabel }: { title: string; peak: Peak | null; formatLabel: (label: string) => string }) {
  return <div>
    <dt>{title}</dt>
    <dd>{peak ? `${formatLabel(peak.label)} · ${peak.count.toLocaleString("es-AR")}` : "Sin datos"}</dd>
  </div>;
}

function OrderCard({ order, token, refresh }: { order: Order; token: string; refresh: () => void }) {
  const [decision, setDecision] = useState("confirmed");
  const state = stateOf(order);
  const address = order.mode === "delivery" ? order.address : order.pickup_address;
  const request = async (operation: string, fields: Record<string, unknown> = {}) => {
    await requestApi("market", {
      action: "orders", operation, orderId: order.id, expectedVersion: order.version, ...fields,
    }, token);
    refresh();
  };
  return (
    <details>
      <summary>Pedido {order.id.slice(0, 8)} · {states[state] ?? state}</summary>
      {order.created_at && <p>{new Date(order.created_at).toLocaleString("es-AR")}</p>}
      <p>{order.mode === "delivery" ? "Envío" : "Retiro"}{address ? ` · ${address}` : ""}</p>
      {order.customer_phone && /^\+[1-9][0-9]{1,14}$/.test(order.customer_phone) && (
        <a className="button secondary" href={`https://wa.me/${order.customer_phone.slice(1)}`}
          target="_blank" rel="noopener noreferrer">Contactar al cliente por WhatsApp</a>
      )}
      {!!order.items.length && <ul>{order.items.map((line) => (
        <li key={line.offer_id}>{line.quantity} × {line.name}</li>
      ))}</ul>}
      <p>Productos: {formatPrice(order.subtotal)}</p>
      {order.mode === "delivery" && <p>Envío: {order.delivery_fee === null ? "A acordar" : formatPrice(order.delivery_fee)}</p>}
      {order.window && <p>Franja acordada: {order.window}</p>}
      {order.reason && <p>Motivo: {order.reason}</p>}
      {order.proposal && <ProposalDetails proposal={order.proposal} />}
      {state === "received" && (
        <>
          <ActionForm success="Decisión guardada." submit={(form) => request("decide", {
            decision, reason: valueOf(form, "reason") || undefined,
          })}>
            <label className="field">Decisión<select value={decision} onChange={(event) => setDecision(event.target.value)}>
              <option value="confirmed">Confirmar</option><option value="rejected">Rechazar</option>
            </select></label>
            {decision === "rejected" && <label className="field">Motivo<input name="reason" maxLength={1000} required /></label>}
            <FormButton>Guardar decisión</FormButton>
          </ActionForm>
          <details>
            <summary>Proponer un cambio de entrega</summary>
            <ActionForm success="Propuesta enviada al cliente." submit={async (form) => {
              const mode = valueOf(form, "mode");
              const address = valueOf(form, "address");
              const deliveryFee = valueOf(form, "deliveryFee");
              const window = valueOf(form, "window");
              if (!mode && !address && !deliveryFee && !window) throw new Error("Ingresá al menos un cambio.");
              await request("propose", {
                mode: mode || undefined, address: address || undefined,
                deliveryFee: deliveryFee ? amountInMinor(deliveryFee, true) : undefined,
                window: window || undefined,
              });
            }}>
              <label className="field">Modalidad<select name="mode" defaultValue="">
                <option value="">Mantener modalidad</option><option value="pickup">Retiro</option><option value="delivery">Envío</option>
              </select></label>
              <label className="field">Nueva dirección de envío<input name="address" maxLength={400} /></label>
              <label className="field">Nuevo cargo de envío en pesos<input name="deliveryFee" inputMode="decimal" /></label>
              <label className="field">Nueva franja comprometida<input name="window" maxLength={120} /></label>
              <FormButton>Enviar propuesta</FormButton>
            </ActionForm>
          </details>
        </>
      )}
      {state === "confirmed" && (
        <>
          <ActionForm success="Pedido completado." submit={() => request("complete")}>
            <FormButton>Marcar como completado</FormButton>
          </ActionForm>
          <ActionForm success="Pedido cancelado." submit={(form) => request("cancel", { reason: valueOf(form, "reason") })}>
            <label className="field">Motivo de cancelación<input name="reason" maxLength={1000} required /></label>
            <FormButton>Cancelar pedido</FormButton>
          </ActionForm>
        </>
      )}
    </details>
  );
}

function ProposalDetails({ proposal }: { proposal: NonNullable<Order["proposal"]> }) {
  const labels: Record<string, string> = { pending: "Pendiente", accepted: "Aceptada", rejected: "Rechazada" };
  return (
    <p>Propuesta de entrega: {labels[proposal.status ?? ""] ?? "Registrada"}
      {proposal.mode && ` · ${proposal.mode === "delivery" ? "Envío" : "Retiro"}`}
      {proposal.address && ` · ${proposal.address}`}
      {typeof proposal.delivery_fee === "number" && ` · ${formatPrice(proposal.delivery_fee)}`}
      {proposal.window && ` · ${proposal.window}`}</p>
  );
}
