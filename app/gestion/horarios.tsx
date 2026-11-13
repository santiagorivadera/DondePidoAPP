"use client";

import { useState } from "react";
import { requestApi } from "../session";
import { ActionForm, FormButton } from "./forms";

const dayNames = ["Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado", "Domingo"];
type Interval = { start: string; end: string };
type Day = { allDay: boolean; intervals: Interval[] };
type SavedDay = { weekday: number; intervals: [number, number][] };

function minutes(time: string): number {
  const [hour, minute] = time.split(":").map(Number);
  return hour * 60 + minute;
}

function clock(minutes: number) {
  return `${String(Math.floor(minutes / 60) % 24).padStart(2, "0")}:${String(minutes % 60).padStart(2, "0")}`;
}

function fromSaved(saved: SavedDay[], index: number): Day {
  const intervals = saved.find((day) => day.weekday === index + 1)?.intervals ?? [];
  if (intervals.length === 1 && intervals[0][0] === 0 && intervals[0][1] === 1440) {
    return { allDay: true, intervals: [] };
  }
  return { allDay: false, intervals: intervals.map(([start, end]) => ({ start: clock(start), end: clock(end) })) };
}

export function HoursForm({ businessId, token, savedHours = [] }: {
  businessId: string;
  token: string;
  savedHours?: SavedDay[];
}) {
  const [days, setDays] = useState<Day[]>(() => dayNames.map((_, index) => fromSaved(savedHours, index)));

  function change(dayIndex: number, changeDay: (day: Day) => Day) {
    setDays((current) => current.map((day, index) => index === dayIndex ? changeDay(day) : day));
  }

  return (
    <ActionForm success="Horarios guardados." submit={async () => {
      const hours = days.map((day, index) => ({
        weekday: index + 1,
        intervals: day.allDay ? [[0, 1440]] : day.intervals.map(({ start, end }) => [minutes(start), minutes(end)]),
      }));
      await requestApi("onboarding", { action: "business.hours", businessId, hours }, token);
    }}>
      <p className="muted">Guardá la grilla completa. Los días sin tramos figuran cerrados.</p>
      {days.map((day, index) => (
        <fieldset key={dayNames[index]}>
          <legend>{dayNames[index]}</legend>
          <label><input type="checkbox" checked={day.allDay}
            onChange={(event) => change(index, (old) => ({ ...old, allDay: event.target.checked }))} /> Abierto las 24 horas</label>
          {!day.allDay && day.intervals.map((interval, row) => (
            <div className="gestion-fields" key={row}>
              <label className="field">Desde<input type="time" value={interval.start} required
                onChange={(event) => change(index, (old) => ({
                  ...old, intervals: old.intervals.map((item, i) => i === row ? { ...item, start: event.target.value } : item),
                }))} /></label>
              <label className="field">Hasta<input type="time" value={interval.end} required
                onChange={(event) => change(index, (old) => ({
                  ...old, intervals: old.intervals.map((item, i) => i === row ? { ...item, end: event.target.value } : item),
                }))} /></label>
              <button className="button secondary" type="button" onClick={() => change(index, (old) => ({
                ...old, intervals: old.intervals.filter((_, i) => i !== row),
              }))}>Quitar tramo</button>
            </div>
          ))}
          {!day.allDay && <button className="button secondary" type="button" onClick={() => change(index, (old) => ({
            ...old, intervals: [...old.intervals, { start: "09:00", end: "18:00" }],
          }))}>Agregar tramo</button>}
        </fieldset>
      ))}
      <FormButton>Guardar horarios</FormButton>
    </ActionForm>
  );
}
