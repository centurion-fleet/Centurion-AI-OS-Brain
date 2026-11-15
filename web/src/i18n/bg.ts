import type { Translations } from "./types";
import { en } from "./en";

/**
 * Bulgarian (bg) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const bg: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Запази",
    saving: "Запазване...",
    cancel: "Отказ",
    close: "Затвори",
    confirm: "Потвърди",
    delete: "Изтрий",
    refresh: "Опресни",
    retry: "Опитай отново",
    search: "Търсене...",
    loading: "Зареждане...",
    create: "Създай",
    creating: "Създаване...",
    set: "Задай",
    replace: "Замени",
    clear: "Изчисти",
    live: "На живо",
    off: "Изкл.",
    enabled: "включено",
    disabled: "изключено",
    active: "активно",
    inactive: "неактивно",
    unknown: "неизвестно",
    untitled: "Без заглавие",
    none: "Няма",
    form: "Формуляр",
    noResults: "Няма резултати",
    of: "от",
    page: "Страница",
    msgs: "съобщ.",
    tools: "инструменти",
    match: "съвпадение",
    other: "Друго",
    configured: "конфигурирано",
    removed: "премахнато",
    failedToToggle: "Неуспешно превключване",
    failedToRemove: "Неуспешно премахване",
    failedToReveal: "Неуспешно показване",
    collapse: "Свий",
    expand: "Разгъни",
    general: "Общи",
    messaging: "Съобщения",
    pluginLoadFailed:
      "Скриптът на този плъгин не можа да се зареди. Проверете раздела Network (dashboard-plugins/…) и пътя до плъгините на сървъра.",
    pluginNotRegistered:
      "Скриптът на плъгина не извика register() или скриптът върна грешка. Отворете конзолата на браузъра за подробности.",
  },
  language: {
    ...en.language,
    switchTo: "Смени езика",
  },
};
