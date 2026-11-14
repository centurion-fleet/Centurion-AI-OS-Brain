import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";
import { getCurrentLocale, getCurrentTranslations } from "@/i18n/current";

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}

/** Mondwest font only — use on layout shells; do not force normal-case here or `text-display` chrome (Segmented, badges) stops uppercasing. */
export const themedFont = "font-mondwest";

/** Mondwest body copy — sentence-case themed text (not uppercase chrome). */
export const themedBody = "font-mondwest normal-case";

/** Mondwest brand chrome — uppercase section headers and nav labels. */
export const themedChrome = "font-mondwest text-display";

/**
 * Relative time, in the interface's language.
 *
 * These used to be hardcoded English — "35m ago" sat inside a Dutch dashboard,
 * which is the sort of thing that makes a translated product feel translated
 * rather than native. `Intl.RelativeTimeFormat` is built into every browser we
 * support and knows the plural rules of all eighteen languages, so this is
 * localised without a single catalogue key to translate or keep in sync.
 */
const FORMATTERS = new Map<string, Intl.RelativeTimeFormat>();

function relative(value: number, unit: Intl.RelativeTimeFormatUnit): string {
  const locale = getCurrentLocale();
  try {
    let fmt = FORMATTERS.get(locale);
    if (!fmt) {
      fmt = new Intl.RelativeTimeFormat(locale, { numeric: "auto" });
      FORMATTERS.set(locale, fmt);
    }
    return fmt.format(value, unit);
  } catch {
    // No Intl, or a locale tag it rejects: say something true in English
    // rather than throw inside a render.
    const n = Math.abs(value);
    return unit === "minute"
      ? `${n}m ago`
      : unit === "hour"
        ? `${n}h ago`
        : unit === "day"
          ? `${n === 1 ? "yesterday" : `${n}d ago`}`
          : "just now";
  }
}

function relativeFrom(seconds: number): string {
  if (seconds < 60) return relative(-1, "second");
  if (seconds < 3600) return relative(-Math.floor(seconds / 60), "minute");
  if (seconds < 86400) return relative(-Math.floor(seconds / 3600), "hour");
  if (seconds < 172800) return relative(-1, "day");
  return relative(-Math.floor(seconds / 86400), "day");
}

/** Relative time from a Unix epoch timestamp (seconds). */
export function timeAgo(ts: number, locale?: string): string {
  void locale; // kept for call-site compatibility; the active locale is global
  return relativeFrom(Date.now() / 1000 - ts);
}

/** Relative time from an ISO-8601 timestamp string. */
export function isoTimeAgo(iso: string, locale?: string): string {
  void locale;
  const delta = (Date.now() - new Date(iso).getTime()) / 1000;
  if (delta < 0 || Number.isNaN(delta)) return getCurrentTranslations().common.unknown;
  return relativeFrom(delta);
}
