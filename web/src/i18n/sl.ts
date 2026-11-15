import type { Translations } from "./types";
import { en } from "./en";

/**
 * Slovene (sl) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const sl: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Shrani",
    saving: "Shranjevanje...",
    cancel: "Prekliči",
    close: "Zapri",
    confirm: "Potrdi",
    delete: "Izbriši",
    refresh: "Osveži",
    retry: "Poskusi znova",
    search: "Iskanje...",
    loading: "Nalaganje...",
    create: "Ustvari",
    creating: "Ustvarjanje...",
    set: "Nastavi",
    replace: "Zamenjaj",
    clear: "Počisti",
    live: "V živo",
    off: "Izklopljeno",
    enabled: "omogočeno",
    disabled: "onemogočeno",
    active: "aktivno",
    inactive: "neaktivno",
    unknown: "neznano",
    untitled: "Brez naslova",
    none: "Brez",
    form: "Obrazec",
    noResults: "Ni rezultatov",
    of: "od",
    page: "Stran",
    msgs: "sporočila",
    tools: "orodja",
    match: "ujemanje",
    other: "Drugo",
    configured: "konfigurirano",
    removed: "odstranjeno",
    failedToToggle: "Preklop ni uspel",
    failedToRemove: "Odstranitev ni uspela",
    failedToReveal: "Prikaz ni uspel",
    collapse: "Strni",
    expand: "Razširi",
    general: "Splošno",
    messaging: "Sporočila",
    pluginLoadFailed:
      "Skripta tega vtičnika ni bilo mogoče naložiti. Preverite zavihek Omrežje (dashboard-plugins/…) in pot do vtičnikov na strežniku.",
    pluginNotRegistered:
      "Skripta vtičnika ni poklicala register() ali pa je prišlo do napake. Podrobnosti so v konzoli brskalnika.",
  },
  language: {
    ...en.language,
    switchTo: "Spremeni jezik",
  },
};
