import type { Translations } from "./types";
import { en } from "./en";

/**
 * Estonian (et) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const et: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Salvesta",
    saving: "Salvestamine...",
    cancel: "Tühista",
    close: "Sulge",
    confirm: "Kinnita",
    delete: "Kustuta",
    refresh: "Värskenda",
    retry: "Proovi uuesti",
    search: "Otsi...",
    loading: "Laadimine...",
    create: "Loo",
    creating: "Loomine...",
    set: "Määra",
    replace: "Asenda",
    clear: "Tühjenda",
    live: "Reaalajas",
    off: "Väljas",
    enabled: "lubatud",
    disabled: "keelatud",
    active: "aktiivne",
    inactive: "mitteaktiivne",
    unknown: "teadmata",
    untitled: "Pealkirjata",
    none: "Puudub",
    form: "Vorm",
    noResults: "Tulemusi pole",
    of: "/",
    page: "Lehekülg",
    msgs: "sõnumit",
    tools: "tööriistad",
    match: "vaste",
    other: "Muu",
    configured: "seadistatud",
    removed: "eemaldatud",
    failedToToggle: "Lülitamine ebaõnnestus",
    failedToRemove: "Eemaldamine ebaõnnestus",
    failedToReveal: "Näitamine ebaõnnestus",
    collapse: "Ahenda",
    expand: "Laienda",
    general: "Üldine",
    messaging: "Sõnumid",
    pluginLoadFailed:
      "Selle pistikprogrammi skripti laadimine ebaõnnestus. Kontrollige Network-kaarti (dashboard-plugins/…) ja serveri pistikprogrammide teed.",
    pluginNotRegistered:
      "Pistikprogrammi skript ei kutsunud välja register() või skript andis vea. Üksikasju vaadake brauseri konsoolist.",
  },
  language: {
    ...en.language,
    switchTo: "Muuda keelt",
  },
};
