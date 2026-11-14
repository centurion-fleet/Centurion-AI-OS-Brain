/**
 * The language the interface is currently in, readable from non-React code.
 *
 * Date formatting and relative times live in `lib/utils.ts`, which is imported
 * by pages, by the plugin registry and by plugins themselves — none of which
 * sit inside a React tree that can call `useI18n()`. Threading a locale
 * argument through every call site would touch six components and break the
 * plugin API for the sake of "35m ago"; a module-level pointer set by the
 * provider is one line and cannot go stale, because the provider is the only
 * thing that ever changes the locale.
 */
import type { Locale, Translations } from "./types";
import { en } from "./en";

let currentLocale: Locale = "en";
let currentTranslations: Translations = en;

export function setCurrentLocale(locale: Locale, translations: Translations): void {
  currentLocale = locale;
  currentTranslations = translations;
}

export function getCurrentLocale(): Locale {
  return currentLocale;
}

export function getCurrentTranslations(): Translations {
  return currentTranslations;
}
