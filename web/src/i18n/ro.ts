import type { Translations } from "./types";
import { en } from "./en";

/**
 * Romanian (ro) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const ro: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Salvează",
    saving: "Se salvează...",
    cancel: "Anulează",
    close: "Închide",
    confirm: "Confirmă",
    delete: "Șterge",
    refresh: "Reîmprospătează",
    retry: "Reîncearcă",
    search: "Caută...",
    loading: "Se încarcă...",
    create: "Creează",
    creating: "Se creează...",
    set: "Setează",
    replace: "Înlocuiește",
    clear: "Golește",
    live: "Live",
    off: "Oprit",
    enabled: "activat",
    disabled: "dezactivat",
    active: "activ",
    inactive: "inactiv",
    unknown: "necunoscut",
    untitled: "Fără titlu",
    none: "Niciunul",
    form: "Formular",
    noResults: "Niciun rezultat",
    of: "din",
    page: "Pagina",
    msgs: "mesaje",
    tools: "unelte",
    match: "potrivire",
    other: "Altele",
    configured: "configurat",
    removed: "eliminat",
    failedToToggle: "Comutarea a eșuat",
    failedToRemove: "Eliminarea a eșuat",
    failedToReveal: "Afișarea a eșuat",
    collapse: "Restrânge",
    expand: "Extinde",
    general: "General",
    messaging: "Mesagerie",
    pluginLoadFailed:
      "Nu s-a putut încărca scriptul acestui plugin. Verifică fila Rețea (dashboard-plugins/…) și calea plugin-urilor de pe server.",
    pluginNotRegistered:
      "Scriptul plugin-ului nu a apelat register() sau a generat o eroare. Deschide consola browserului pentru detalii.",
  },
  language: {
    ...en.language,
    switchTo: "Schimbă limba",
  },
};
