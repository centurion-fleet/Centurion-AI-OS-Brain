import type { Translations } from "./types";
import { en } from "./en";

/**
 * Finnish (fi) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const fi: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Tallenna",
    saving: "Tallennetaan...",
    cancel: "Peruuta",
    close: "Sulje",
    confirm: "Vahvista",
    delete: "Poista",
    refresh: "Päivitä",
    retry: "Yritä uudelleen",
    search: "Hae...",
    loading: "Ladataan...",
    create: "Luo",
    creating: "Luodaan...",
    set: "Aseta",
    replace: "Korvaa",
    clear: "Tyhjennä",
    live: "Live",
    off: "Pois",
    enabled: "käytössä",
    disabled: "pois käytöstä",
    active: "aktiivinen",
    inactive: "ei aktiivinen",
    unknown: "tuntematon",
    untitled: "Nimetön",
    none: "Ei mitään",
    form: "Lomake",
    noResults: "Ei tuloksia",
    of: "/",
    page: "Sivu",
    msgs: "viestiä",
    tools: "työkalut",
    match: "osuma",
    other: "Muu",
    configured: "määritetty",
    removed: "poistettu",
    failedToToggle: "Vaihtaminen epäonnistui",
    failedToRemove: "Poistaminen epäonnistui",
    failedToReveal: "Näyttäminen epäonnistui",
    collapse: "Kutista",
    expand: "Laajenna",
    general: "Yleiset",
    messaging: "Viestit",
    pluginLoadFailed:
      "Tämän laajennuksen skriptiä ei voitu ladata. Tarkista Network-välilehti (dashboard-plugins/…) ja palvelimen laajennuspolku.",
    pluginNotRegistered:
      "Laajennuksen skripti ei kutsunut register()-funktiota tai skripti epäonnistui. Avaa selaimen konsoli nähdäksesi lisätiedot.",
  },
  language: {
    ...en.language,
    switchTo: "Vaihda kieli",
  },
};
