import type { Translations } from "./types";
import { en } from "./en";

/**
 * Croatian (hr) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const hr: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Spremi",
    saving: "Spremanje...",
    cancel: "Odustani",
    close: "Zatvori",
    confirm: "Potvrdi",
    delete: "Izbriši",
    refresh: "Osvježi",
    retry: "Pokušaj ponovno",
    search: "Pretraži...",
    loading: "Učitavanje...",
    create: "Stvori",
    creating: "Stvaranje...",
    set: "Postavi",
    replace: "Zamijeni",
    clear: "Očisti",
    live: "Uživo",
    off: "Isključeno",
    enabled: "omogućeno",
    disabled: "onemogućeno",
    active: "aktivno",
    inactive: "neaktivno",
    unknown: "nepoznato",
    untitled: "Bez naslova",
    none: "Nema",
    form: "Obrazac",
    noResults: "Nema rezultata",
    of: "od",
    page: "Stranica",
    msgs: "poruka",
    tools: "alati",
    match: "podudaranje",
    other: "Ostalo",
    configured: "konfigurirano",
    removed: "uklonjeno",
    failedToToggle: "Promjena nije uspjela",
    failedToRemove: "Uklanjanje nije uspjelo",
    failedToReveal: "Prikazivanje nije uspjelo",
    collapse: "Skupi",
    expand: "Proširi",
    general: "Općenito",
    messaging: "Poruke",
    pluginLoadFailed:
      "Skriptu ovog dodatka nije bilo moguće učitati. Provjerite karticu Network (dashboard-plugins/…) i putanju dodataka na poslužitelju.",
    pluginNotRegistered:
      "Skripta dodatka nije pozvala register() ili je skripta vratila pogrešku. Otvorite konzolu preglednika za pojedinosti.",
  },
  language: {
    ...en.language,
    switchTo: "Promijeni jezik",
  },
};
