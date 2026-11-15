import type { Translations } from "./types";
import { en } from "./en";

/**
 * Latvian (lv) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const lv: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Saglabāt",
    saving: "Saglabā...",
    cancel: "Atcelt",
    close: "Aizvērt",
    confirm: "Apstiprināt",
    delete: "Dzēst",
    refresh: "Atsvaidzināt",
    retry: "Mēģināt vēlreiz",
    search: "Meklēt...",
    loading: "Ielādē...",
    create: "Izveidot",
    creating: "Izveido...",
    set: "Iestatīt",
    replace: "Aizstāt",
    clear: "Notīrīt",
    live: "Tiešraide",
    off: "Izslēgts",
    enabled: "iespējots",
    disabled: "atspējots",
    active: "aktīvs",
    inactive: "neaktīvs",
    unknown: "nezināms",
    untitled: "Bez nosaukuma",
    none: "Nav",
    form: "Veidlapa",
    noResults: "Nav rezultātu",
    of: "no",
    page: "Lapa",
    msgs: "ziņas",
    tools: "rīki",
    match: "atbilstība",
    other: "Cits",
    configured: "konfigurēts",
    removed: "noņemts",
    failedToToggle: "Neizdevās pārslēgt",
    failedToRemove: "Neizdevās noņemt",
    failedToReveal: "Neizdevās parādīt",
    collapse: "Sakļaut",
    expand: "Izvērst",
    general: "Vispārīgi",
    messaging: "Ziņojumi",
    pluginLoadFailed:
      "Neizdevās ielādēt šī spraudņa skriptu. Pārbaudiet tīkla cilni (dashboard-plugins/…) un servera spraudņu ceļu.",
    pluginNotRegistered:
      "Spraudņa skripts neizsauca register() vai arī radās kļūda. Atveriet pārlūka konsoli, lai uzzinātu detaļas.",
  },
  language: {
    ...en.language,
    switchTo: "Mainīt valodu",
  },
};
