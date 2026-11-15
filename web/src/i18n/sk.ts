import type { Translations } from "./types";
import { en } from "./en";

/**
 * Slovak (sk) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const sk: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Uložiť",
    saving: "Ukladá sa...",
    cancel: "Zrušiť",
    close: "Zavrieť",
    confirm: "Potvrdiť",
    delete: "Odstrániť",
    refresh: "Obnoviť",
    retry: "Skúsiť znova",
    search: "Hľadať...",
    loading: "Načítava sa...",
    create: "Vytvoriť",
    creating: "Vytvára sa...",
    set: "Nastaviť",
    replace: "Nahradiť",
    clear: "Vymazať",
    live: "Naživo",
    off: "Vypnuté",
    enabled: "povolené",
    disabled: "zakázané",
    active: "aktívne",
    inactive: "neaktívne",
    unknown: "neznáme",
    untitled: "Bez názvu",
    none: "Žiadne",
    form: "Formulár",
    noResults: "Žiadne výsledky",
    of: "z",
    page: "Strana",
    msgs: "správy",
    tools: "nástroje",
    match: "zhoda",
    other: "Iné",
    configured: "nakonfigurované",
    removed: "odstránené",
    failedToToggle: "Prepnutie zlyhalo",
    failedToRemove: "Odstránenie zlyhalo",
    failedToReveal: "Zobrazenie zlyhalo",
    collapse: "Zbaliť",
    expand: "Rozbaliť",
    general: "Všeobecné",
    messaging: "Správy",
    pluginLoadFailed:
      "Tento skript pluginu sa nepodarilo načítať. Skontrolujte kartu Sieť (dashboard-plugins/…) a cestu k pluginom na serveri.",
    pluginNotRegistered:
      "Skript pluginu nevyvolal register() alebo nastala chyba. Podrobnosti nájdete v konzole prehliadača.",
  },
  language: {
    ...en.language,
    switchTo: "Zmeniť jazyk",
  },
};
