import {
  createContext,
  useContext,
  useState,
  useCallback,
  useEffect,
  useRef,
  type ReactNode,
} from "react";
import type { Locale, Translations } from "./types";
import { en } from "./en";
import { zh } from "./zh";
import { zhHant } from "./zh-hant";
import { ja } from "./ja";
import { de } from "./de";
import { es } from "./es";
import { fr } from "./fr";
import { tr } from "./tr";
import { uk } from "./uk";
import { af } from "./af";
import { ko } from "./ko";
import { it } from "./it";
import { ga } from "./ga";
import { pt } from "./pt";
import { ru } from "./ru";
import { hu } from "./hu";
import { nl } from "./nl";
import { pl } from "./pl";
import { setCurrentLocale } from "./current";
import { api } from "@/lib/api";

const TRANSLATIONS: Record<Locale, Translations> = {
  en,
  fr,
  de,
  nl,
  pl,
  es,
  it,
  pt,
  zh,
  "zh-hant": zhHant,
  ja,
  tr,
  uk,
  af,
  ko,
  ga,
  ru,
  hu,
};

// Display metadata for the language picker — endonym (native name) so users
// recognize their language even if they don't speak the current UI language.
// Exposed as a constant so the LanguageSwitcher and any future settings page
// can share the same list.
//
// We intentionally do NOT pair locales with country flags. Languages are not
// countries (English ≠ GB, Portuguese ≠ PT, Spanish ≠ ES, Chinese variants ≠
// any single jurisdiction). Endonyms are unambiguous and avoid the political
// mismapping that flag pairings inevitably create.
export const LOCALE_META: Record<Locale, { name: string }> = {
  // Ordered by market, not alphabetically: the eleven locales the website
  // sells are first, so a buyer whose page was in Dutch finds Dutch at the
  // top of the list rather than eight entries down. The rest are kept -- a
  // language we ship is a language somebody may read in.
  en: { name: "English" },
  fr: { name: "Français" },
  de: { name: "Deutsch" },
  nl: { name: "Nederlands" },
  pl: { name: "Polski" },
  es: { name: "Español" },
  it: { name: "Italiano" },
  pt: { name: "Português" },
  zh: { name: "简体中文" },
  "zh-hant": { name: "繁體中文" },
  ja: { name: "日本語" },
  tr: { name: "Türkçe" },
  uk: { name: "Українська" },
  af: { name: "Afrikaans" },
  ko: { name: "한국어" },
  ga: { name: "Gaeilge" },
  ru: { name: "Русский" },
  hu: { name: "Magyar" },
};

const SUPPORTED_LOCALES = Object.keys(TRANSLATIONS) as Locale[];
const STORAGE_KEY = "centurion-locale";

function isLocale(value: string): value is Locale {
  return (SUPPORTED_LOCALES as string[]).includes(value);
}

function getInitialLocale(): Locale {
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored && isLocale(stored)) return stored;
  } catch {
    // SSR or privacy mode
  }
  return "en";
}

interface I18nContextValue {
  locale: Locale;
  setLocale: (l: Locale) => void;
  t: Translations;
}

const I18nContext = createContext<I18nContextValue>({
  locale: "en",
  setLocale: () => {},
  t: en,
});

export function I18nProvider({ children }: { children: ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>(getInitialLocale);
  // localStorage holds what this browser last showed; the server holds what the
  // Brain IS. Until the server answers, the local value is only a guess, so the
  // first fetch wins — otherwise a stale browser value would silently overwrite
  // a language the owner set on the machine itself.
  const hydrated = useRef(false);

  useEffect(() => {
    let cancelled = false;
    api
      .getLanguage()
      .then((res) => {
        if (cancelled) return;
        if (isLocale(res.language) && res.language !== locale) {
          setLocaleState(res.language);
        }
        hydrated.current = true;
        try {
          localStorage.setItem(STORAGE_KEY, res.language);
        } catch {
          // ignore
        }
      })
      .catch(() => {
        // A dashboard opened without the server (SSR, tests) keeps the local
        // value rather than flashing English over a working interface.
        hydrated.current = true;
      });
    return () => {
      cancelled = true;
    };
    // Intentionally once, on mount: the server is the source of truth.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const setLocale = useCallback(
    (l: Locale) => {
      // Optimistic: the interface changes immediately, because a language menu
      // that waits for a round trip feels broken.
      setLocaleState(l);
      try {
        localStorage.setItem(STORAGE_KEY, l);
      } catch {
        // ignore
      }
      // Persisted so the Python side learns it: the agent reads
      // display.language, and an interface-only switch is a decoration.
      api.setLanguage(l).catch((err) => {
        console.error("Could not save the language setting:", err);
      });
    },
    [],
  );

  // Non-React code (date formatting, plugins) reads the locale through this
  // pointer, so every change — mount, server hydration, menu click — has to
  // write it. It is derived state, so it is set during render rather than in
  // an effect: a wrong-language "35m ago" for one frame is still a bug.
  setCurrentLocale(locale, TRANSLATIONS[locale]);

  // Tell assistive tech and the browser which language this page is in --
  // otherwise a Dutch interface is announced in English phonemes and the
  // hyphenation and spell-check follow the wrong language too.
  if (typeof document !== "undefined") {
    document.documentElement.lang = locale;
  }

  const value: I18nContextValue = {
    locale,
    setLocale,
    t: TRANSLATIONS[locale],
  };

  return <I18nContext.Provider value={value}>{children}</I18nContext.Provider>;
}

export function useI18n() {
  return useContext(I18nContext);
}
