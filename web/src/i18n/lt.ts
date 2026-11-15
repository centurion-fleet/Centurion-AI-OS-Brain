import type { Translations } from "./types";
import { en } from "./en";

/**
 * Lithuanian (lt) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const lt: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Išsaugoti",
    saving: "Išsaugoma...",
    cancel: "Atšaukti",
    close: "Uždaryti",
    confirm: "Patvirtinti",
    delete: "Ištrinti",
    refresh: "Atnaujinti",
    retry: "Bandyti dar kartą",
    search: "Ieškoti...",
    loading: "Įkeliama...",
    create: "Sukurti",
    creating: "Kuriama...",
    set: "Nustatyti",
    replace: "Pakeisti",
    clear: "Išvalyti",
    live: "Tiesiogiai",
    off: "Išjungta",
    enabled: "įjungta",
    disabled: "išjungta",
    active: "aktyvi",
    inactive: "neaktyvi",
    unknown: "nežinoma",
    untitled: "Be pavadinimo",
    none: "Nėra",
    form: "Forma",
    noResults: "Nėra rezultatų",
    of: "iš",
    page: "Puslapis",
    msgs: "žinutės",
    tools: "įrankiai",
    match: "atitikmuo",
    other: "Kita",
    configured: "sukonfigūruota",
    removed: "pašalinta",
    failedToToggle: "Nepavyko perjungti",
    failedToRemove: "Nepavyko pašalinti",
    failedToReveal: "Nepavyko parodyti",
    collapse: "Sutraukti",
    expand: "Išskleisti",
    general: "Bendra",
    messaging: "Žinutės",
    pluginLoadFailed:
      "Nepavyko įkelti šio papildinio scenarijaus. Patikrinkite tinklo skirtuką (dashboard-plugins/…) ir serverio papildinių kelią.",
    pluginNotRegistered:
      "Papildinio scenarijus neiškvietė register() arba įvyko klaida. Atidarykite naršyklės konsolę išsamesnei informacijai.",
  },
  language: {
    ...en.language,
    switchTo: "Keisti kalbą",
  },
};
