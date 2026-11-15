import type { Translations } from "./types";
import { en } from "./en";

/**
 * Greek (el) — dashboard shell vocabulary.
 *
 * Translated: `common` (the words every screen uses) and `language` (this
 * picker's own labels). Everything else inherits English through the spread,
 * because an untranslated label that says something is usable and a missing
 * one is a blank button. Full translation is incremental from here.
 */
export const el: Translations = {
  ...en,
  common: {
    ...en.common,
    save: "Αποθήκευση",
    saving: "Αποθήκευση...",
    cancel: "Ακύρωση",
    close: "Κλείσιμο",
    confirm: "Επιβεβαίωση",
    delete: "Διαγραφή",
    refresh: "Ανανέωση",
    retry: "Δοκιμή ξανά",
    search: "Αναζήτηση...",
    loading: "Φόρτωση...",
    create: "Δημιουργία",
    creating: "Δημιουργία...",
    set: "Ορισμός",
    replace: "Αντικατάσταση",
    clear: "Καθαρισμός",
    live: "Ζωντανά",
    off: "Κλειστό",
    enabled: "ενεργοποιημένο",
    disabled: "απενεργοποιημένο",
    active: "ενεργό",
    inactive: "ανενεργό",
    unknown: "άγνωστο",
    untitled: "Χωρίς τίτλο",
    none: "Κανένα",
    form: "Φόρμα",
    noResults: "Κανένα αποτέλεσμα",
    of: "από",
    page: "Σελίδα",
    msgs: "μηνύματα",
    tools: "εργαλεία",
    match: "αντιστοιχία",
    other: "Άλλο",
    configured: "ρυθμισμένο",
    removed: "αφαιρέθηκε",
    failedToToggle: "Αποτυχία εναλλαγής",
    failedToRemove: "Αποτυχία αφαίρεσης",
    failedToReveal: "Αποτυχία εμφάνισης",
    collapse: "Σύμπτυξη",
    expand: "Ανάπτυξη",
    general: "Γενικά",
    messaging: "Μηνύματα",
    pluginLoadFailed:
      "Δεν ήταν δυνατή η φόρτωση του script αυτού του plugin. Ελέγξτε την καρτέλα Network (dashboard-plugins/…) και τη διαδρομή plugin του διακομιστή.",
    pluginNotRegistered:
      "Το script του plugin δεν κάλεσε το register() ή το script απέτυχε. Ανοίξτε την κονσόλα του προγράμματος περιήγησης για λεπτομέρειες.",
  },
  language: {
    ...en.language,
    switchTo: "Αλλαγή γλώσσας",
  },
};
