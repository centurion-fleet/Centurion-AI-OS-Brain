import type { Translations } from "./types";
import { en } from "./en";

/**
 * Czech (cs) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const cs: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Uložit",
    saving: "Ukládání...",
    cancel: "Zrušit",
    close: "Zavřít",
    confirm: "Potvrdit",
    delete: "Smazat",
    refresh: "Obnovit",
    retry: "Zkusit znovu",
    search: "Hledat...",
    loading: "Načítání...",
    create: "Vytvořit",
    creating: "Vytváření...",
    set: "Nastavit",
    replace: "Nahradit",
    clear: "Vymazat",
    live: "Živě",
    off: "Vyp.",
    enabled: "povoleno",
    disabled: "zakázáno",
    active: "aktivní",
    inactive: "neaktivní",
    unknown: "neznámé",
    untitled: "Bez názvu",
    none: "Žádné",
    form: "Formulář",
    noResults: "Žádné výsledky",
    of: "z",
    page: "Stránka",
    msgs: "zpráv",
    tools: "nástroje",
    match: "shoda",
    other: "Jiné",
    configured: "nakonfigurováno",
    removed: "odstraněno",
    failedToToggle: "Přepnutí se nezdařilo",
    failedToRemove: "Odebrání se nezdařilo",
    failedToReveal: "Zobrazení se nezdařilo",
    collapse: "Sbalit",
    expand: "Rozbalit",
    general: "Obecné",
    messaging: "Zprávy",
    pluginLoadFailed:
      "Skript tohoto pluginu se nepodařilo načíst. Zkontrolujte kartu Network (dashboard-plugins/…) a cestu k pluginům na serveru.",
    pluginNotRegistered:
      "Skript pluginu nezavolal register() nebo skript vrátil chybu. Podrobnosti najdete v konzoli prohlížeče.",
  },
  language: {
    ...en.language,
    switchTo: "Změnit jazyk",
  },
};
