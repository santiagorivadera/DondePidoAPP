import { HttpError, isRecord } from "./http";

type Interval = [start: number, end: number];

function invalidHours(): HttpError {
  return new HttpError(400, "VALIDACION", "Revisá los días y tramos de atención.");
}

export function normalizeWeeklyHours(value: unknown) {
  if (!Array.isArray(value) || value.length > 7) throw invalidHours();

  const weekdays = new Set<number>();
  const normalized: Interval[][] = Array.from({ length: 7 }, () => []);
  for (const day of value as unknown[]) {
    if (!isRecord(day)) throw invalidHours();
    const { weekday, intervals } = day;
    if (typeof weekday !== "number" || !Number.isInteger(weekday) || weekday < 1 || weekday > 7 ||
        weekdays.has(weekday) || !Array.isArray(intervals)) {
      throw invalidHours();
    }
    weekdays.add(weekday);

    for (const interval of intervals as unknown[]) {
      if (!Array.isArray(interval) || interval.length !== 2) throw invalidHours();
      const [start, end]: unknown[] = interval;
      if (typeof start !== "number" || !Number.isInteger(start) || start < 0 || start >= 1440 ||
          typeof end !== "number" || !Number.isInteger(end) || end < 0 || end > 1440 || start === end) {
        throw invalidHours();
      }
      if (start < end) {
        normalized[weekday - 1].push([start, end]);
      } else {
        normalized[weekday - 1].push([start, 1440]);
        if (end > 0) normalized[weekday % 7].push([0, end]);
      }
    }
  }

  return normalized
    .map((intervals, index) => ({ weekday: index + 1, intervals }))
    .filter((day) => day.intervals.length > 0);
}
