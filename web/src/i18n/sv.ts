import type { Translations } from "./types";
import { en } from "./en";

/**
 * Swedish (sv) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const sv: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Spara",
    saving: "Sparar...",
    cancel: "Avbryt",
    close: "Stäng",
    confirm: "Bekräfta",
    delete: "Radera",
    refresh: "Uppdatera",
    retry: "Försök igen",
    search: "Sök...",
    loading: "Laddar...",
    create: "Skapa",
    creating: "Skapar...",
    set: "Ange",
    replace: "Ersätt",
    clear: "Rensa",
    live: "Live",
    off: "Av",
    enabled: "aktiverad",
    disabled: "inaktiverad",
    active: "aktiv",
    inactive: "inaktiv",
    unknown: "okänd",
    untitled: "Namnlös",
    none: "Ingen",
    form: "Formulär",
    noResults: "Inga resultat",
    of: "av",
    page: "Sida",
    msgs: "medd.",
    tools: "verktyg",
    match: "träff",
    other: "Övrigt",
    configured: "konfigurerad",
    removed: "borttagen",
    failedToToggle: "Kunde inte växla",
    failedToRemove: "Kunde inte ta bort",
    failedToReveal: "Kunde inte visa",
    collapse: "Fäll ihop",
    expand: "Fäll ut",
    general: "Allmänt",
    messaging: "Meddelanden",
    pluginLoadFailed:
      "Det gick inte att läsa in det här pluginets skript. Kontrollera fliken Nätverk (dashboard-plugins/…) och serverns pluginsökväg.",
    pluginNotRegistered:
      "Pluginets skript anropade inte register() eller så uppstod ett fel. Öppna webbläsarens konsol för detaljer.",
  },
  language: {
    ...en.language,
    switchTo: "Byt språk",
  },
};
