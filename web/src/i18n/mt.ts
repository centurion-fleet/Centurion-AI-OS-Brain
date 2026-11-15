import type { Translations } from "./types";
import { en } from "./en";

/**
 * Maltese (mt) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const mt: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Issejvja",
    saving: "Qed jissejvja...",
    cancel: "Ikkanċella",
    close: "Agħlaq",
    confirm: "Ikkonferma",
    delete: "Ħassar",
    refresh: "Aġġorna",
    retry: "Erġa' pprova",
    search: "Fittex...",
    loading: "Qed jitgħabba...",
    create: "Oħloq",
    creating: "Qed joħloq...",
    set: "Issettja",
    replace: "Issostitwixxi",
    clear: "Naddaf",
    live: "Live",
    off: "Mitfi",
    enabled: "attivat",
    disabled: "diżattivat",
    active: "attiv",
    inactive: "inattiv",
    unknown: "mhux magħruf",
    untitled: "Mingħajr titlu",
    none: "Xejn",
    form: "Formola",
    noResults: "L-ebda riżultat",
    of: "minn",
    page: "Paġna",
    msgs: "msġ",
    tools: "għodod",
    match: "qbil",
    other: "Oħra",
    configured: "ikkonfigurat",
    removed: "imneħħi",
    failedToToggle: "Ma rnexxietx il-bidla",
    failedToRemove: "Ma rnexxielux jitneħħa",
    failedToReveal: "Ma rnexxielux jintwera",
    collapse: "Ikkollassja",
    expand: "Ifrex",
    general: "Ġenerali",
    messaging: "Messaġġi",
    pluginLoadFailed:
      "Ma setax jitgħabba l-iskript ta' dan il-plugin. Iċċekkja t-tab tan-Network (dashboard-plugins/…) u l-passa tal-plugin tas-server.",
    pluginNotRegistered:
      "L-iskript tal-plugin ma sejjaħx register(), jew l-iskript ta' żball. Iftaħ il-console tal-browser għad-dettalji.",
  },
  language: {
    ...en.language,
    switchTo: "Ibdel il-lingwa",
  },
};
