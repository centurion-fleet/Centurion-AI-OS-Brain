import type { Translations } from "./types";
import { en } from "./en";

/**
 * Danish (da) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const da: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Gem",
    saving: "Gemmer...",
    cancel: "Annuller",
    close: "Luk",
    confirm: "Bekræft",
    delete: "Slet",
    refresh: "Opdater",
    retry: "Prøv igen",
    search: "Søg...",
    loading: "Indlæser...",
    create: "Opret",
    creating: "Opretter...",
    set: "Angiv",
    replace: "Erstat",
    clear: "Ryd",
    live: "Live",
    off: "Fra",
    enabled: "aktiveret",
    disabled: "deaktiveret",
    active: "aktiv",
    inactive: "inaktiv",
    unknown: "ukendt",
    untitled: "Uden titel",
    none: "Ingen",
    form: "Formular",
    noResults: "Ingen resultater",
    of: "af",
    page: "Side",
    msgs: "beskeder",
    tools: "værktøjer",
    match: "match",
    other: "Andet",
    configured: "konfigureret",
    removed: "fjernet",
    failedToToggle: "Kunne ikke skifte",
    failedToRemove: "Kunne ikke fjerne",
    failedToReveal: "Kunne ikke vise",
    collapse: "Skjul",
    expand: "Udvid",
    general: "Generelt",
    messaging: "Beskeder",
    pluginLoadFailed:
      "Kunne ikke indlæse dette plugins script. Tjek Network-fanen (dashboard-plugins/…) og serverens plugin-sti.",
    pluginNotRegistered:
      "Pluginets script kaldte ikke register(), eller scriptet fejlede. Åbn browserkonsollen for detaljer.",
  },
  language: {
    ...en.language,
    switchTo: "Skift sprog",
  },
};
