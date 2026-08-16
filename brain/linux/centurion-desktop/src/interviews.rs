//! Guided Mission Discovery and Shape Your Sovereign interviews for Brain.
//!
//! Question copy aligned with iOS MissionDiscoveryView / SoulInterviewView —
//! do not invent a third narrative.

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;

use crate::chat_page::{clear_desktop_chat_session, run_bridge_action};

struct Question {
    id: &'static str,
    section: &'static str,
    prompt: &'static str,
}

const MISSION_QUESTIONS: &[Question] = &[
    Question {
        id: "areas",
        section: "What Matters Most",
        prompt: "When you look at the world, what areas of life feel most important to you right now?",
    },
    Question {
        id: "topAreas",
        section: "What Matters Most",
        prompt: "If you had to choose 2–3 areas that you care about more than anything else, what would they be?",
    },
    Question {
        id: "responsibility",
        section: "Responsibility & Ownership",
        prompt: "What are you willing to take real responsibility for in your life or in the world?",
    },
    Question {
        id: "problems",
        section: "Responsibility & Ownership",
        prompt: "What problems or situations do you naturally feel drawn to help solve or improve?",
    },
    Question {
        id: "shouldDo",
        section: "Responsibility & Ownership",
        prompt: "What do you feel you should be doing, even if it sometimes feels difficult or scary?",
    },
    Question {
        id: "alive",
        section: "Natural Energy & Aliveness",
        prompt: "When do you feel most alive, engaged, or “in flow”?",
    },
    Question {
        id: "timeless",
        section: "Natural Energy & Aliveness",
        prompt: "What activities or contributions make time disappear for you?",
    },
    Question {
        id: "noLimits",
        section: "Long-term Vision",
        prompt: "If you knew you couldn’t fail, what would you build or contribute over the next 10–20 years?",
    },
    Question {
        id: "endOfLife",
        section: "Long-term Vision",
        prompt: "Looking back from the end of your life, what would make you feel your time was well spent?",
    },
];

const SOUL_QUESTIONS: &[Question] = &[
    Question {
        id: "name",
        section: "Identity",
        prompt: "What is your Centurion's name? (A personal name — not “Centurion”.)",
    },
    Question {
        id: "personalitySummary",
        section: "Identity",
        prompt: "In one or two sentences, who is your Sovereign?",
    },
    Question {
        id: "tone",
        section: "Voice",
        prompt: "What tone should your Sovereign use?",
    },
    Question {
        id: "communicationStyle",
        section: "Voice",
        prompt: "How should your Sovereign speak to you?",
    },
    Question {
        id: "responseLength",
        section: "Voice",
        prompt: "How long should responses usually be?",
    },
    Question {
        id: "alwaysDo",
        section: "Boundaries",
        prompt: "What should your Sovereign always do?",
    },
    Question {
        id: "neverDo",
        section: "Boundaries",
        prompt: "What should your Sovereign never do?",
    },
    Question {
        id: "pushbackStyle",
        section: "Judgment",
        prompt: "When should your Sovereign push back on you?",
    },
    Question {
        id: "uncertaintyStyle",
        section: "Judgment",
        prompt: "How should your Sovereign handle uncertainty?",
    },
];

const ABOUT_YOU_QUESTIONS: &[Question] = &[
    Question {
        id: "yourStory",
        section: "About You",
        prompt: "In a few sentences, what should your Sovereign know about your story?",
    },
    Question {
        id: "yourValues",
        section: "About You",
        prompt: "What values should guide how your Sovereign partners with you?",
    },
    Question {
        id: "workStyle",
        section: "About You",
        prompt: "How do you prefer to work — pace, detail, and collaboration?",
    },
    Question {
        id: "challenges",
        section: "About You",
        prompt: "What challenges are you facing that your Sovereign should keep in mind?",
    },
];

fn synthesize_mission(answers: &HashMap<String, String>) -> (String, String) {
    let top = answers.get("topAreas").cloned().unwrap_or_default();
    let responsibility = answers.get("responsibility").cloned().unwrap_or_default();
    let should = answers.get("shouldDo").cloned().unwrap_or_default();
    let vision = answers.get("noLimits").cloned().unwrap_or_default();
    let end = answers.get("endOfLife").cloned().unwrap_or_default();

    let statement = format!(
        "I am building toward {top}. I take responsibility for {responsibility}. \
I commit to {should}. Over the long term: {vision}. \
A life well spent looks like: {end}."
    )
    .split_whitespace()
    .collect::<Vec<_>>()
    .join(" ");

    let why = format!(
        "Drawn to: {}. Alive when: {}. Timeless work: {}.",
        answers.get("problems").cloned().unwrap_or_default(),
        answers.get("alive").cloned().unwrap_or_default(),
        answers.get("timeless").cloned().unwrap_or_default(),
    );
    (statement, why)
}

fn show_guided_interview(
    parent: &adw::ApplicationWindow,
    title: &str,
    intro: &str,
    questions: &'static [Question],
    on_complete: Rc<dyn Fn(HashMap<String, String>)>,
) {
    let intro_text = intro.to_owned();
    let window = adw::ApplicationWindow::builder()
        .transient_for(parent)
        .modal(true)
        .title(title)
        .default_width(560)
        .default_height(420)
        .build();

    let header = adw::HeaderBar::new();
    let toolbar = adw::ToolbarView::new();
    toolbar.add_top_bar(&header);

    let root = gtk::Box::new(gtk::Orientation::Vertical, 12);
    root.set_margin_top(20);
    root.set_margin_bottom(20);
    root.set_margin_start(24);
    root.set_margin_end(24);

    let section = gtk::Label::builder()
        .label(&intro_text)
        .wrap(true)
        .xalign(0.0)
        .css_classes(["title-4"])
        .build();
    let prompt = gtk::Label::builder()
        .label("")
        .wrap(true)
        .xalign(0.0)
        .build();
    let progress = gtk::Label::builder()
        .label("")
        .xalign(0.0)
        .css_classes(["dim-label", "caption"])
        .build();
    let entry = gtk::TextView::builder()
        .wrap_mode(gtk::WrapMode::WordChar)
        .hexpand(true)
        .vexpand(true)
        .build();
    let scrolled = gtk::ScrolledWindow::builder()
        .child(&entry)
        .min_content_height(140)
        .vexpand(true)
        .build();

    let nav = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    let back = gtk::Button::with_label("Back");
    back.add_css_class("flat");
    let next = gtk::Button::with_label("Next");
    next.add_css_class("suggested-action");
    nav.append(&back);
    let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
    spacer.set_hexpand(true);
    nav.append(&spacer);
    nav.append(&next);

    root.append(&section);
    root.append(&progress);
    root.append(&prompt);
    root.append(&scrolled);
    root.append(&nav);
    toolbar.set_content(Some(&root));
    window.set_content(Some(&toolbar));

    let idx = Rc::new(Cell::new(0_usize));
    let answers: Rc<RefCell<HashMap<String, String>>> = Rc::new(RefCell::new(HashMap::new()));
    let started = Rc::new(Cell::new(false));

    let paint = {
        let section = section.clone();
        let prompt = prompt.clone();
        let progress = progress.clone();
        let entry = entry.clone();
        let idx = idx.clone();
        let answers = answers.clone();
        let back = back.clone();
        let next = next.clone();
        let started = started.clone();
        let intro_text = intro_text.clone();
        Rc::new(move || {
            let i = idx.get();
            if !started.get() {
                section.set_label(&intro_text);
                prompt.set_label("Tap Next when you are ready to begin.");
                progress.set_label("");
                entry.buffer().set_text("");
                back.set_sensitive(false);
                next.set_label("Begin");
                return;
            }
            let q = &questions[i];
            section.set_label(q.section);
            prompt.set_label(q.prompt);
            progress.set_label(&format!("Question {} of {}", i + 1, questions.len()));
            let existing = answers.borrow().get(q.id).cloned().unwrap_or_default();
            entry.buffer().set_text(&existing);
            back.set_sensitive(i > 0);
            next.set_label(if i + 1 >= questions.len() {
                "Finish"
            } else {
                "Next"
            });
        }) as Rc<dyn Fn()>
    };
    paint();

    {
        let idx = idx.clone();
        let answers = answers.clone();
        let entry = entry.clone();
        let started = started.clone();
        let paint = paint.clone();
        let on_complete = on_complete.clone();
        let window = window.clone();
        next.connect_clicked(move |_| {
            if !started.get() {
                started.set(true);
                paint();
                return;
            }
            let i = idx.get();
            let q = &questions[i];
            let (start, end) = entry.buffer().bounds();
            let text = entry.buffer().text(&start, &end, false).trim().to_owned();
            answers.borrow_mut().insert(q.id.to_owned(), text);
            if i + 1 >= questions.len() {
                on_complete(answers.borrow().clone());
                window.close();
            } else {
                idx.set(i + 1);
                paint();
            }
        });
    }
    {
        let idx = idx.clone();
        let entry = entry.clone();
        let answers = answers.clone();
        let started = started.clone();
        let paint = paint.clone();
        back.connect_clicked(move |_| {
            if !started.get() {
                return;
            }
            let i = idx.get();
            if i == 0 {
                return;
            }
            let q = &questions[i];
            let (start, end) = entry.buffer().bounds();
            let text = entry.buffer().text(&start, &end, false).trim().to_owned();
            answers.borrow_mut().insert(q.id.to_owned(), text);
            idx.set(i - 1);
            paint();
        });
    }

    window.present();
}

/// Mission Discovery → synthesizes statement and saves via mission_put.
pub fn show_mission_discovery(parent: &adw::ApplicationWindow, on_saved: Rc<dyn Fn()>) {
    let parent_for_cb = parent.clone();
    show_guided_interview(
        parent,
        "Mission Discovery",
        "A short ceremony to name what you are building toward. Your Sovereign will keep this as your Life Mission.",
        MISSION_QUESTIONS,
        Rc::new(move |answers| {
            let (statement, why) = synthesize_mission(&answers);
            let areas: Vec<String> = answers
                .get("topAreas")
                .map(|s| {
                    s.split([',', ';', '\n'])
                        .map(str::trim)
                        .filter(|p| !p.is_empty())
                        .map(str::to_owned)
                        .collect()
                })
                .unwrap_or_default();
            let targets: Vec<serde_json::Value> = areas
                .iter()
                .enumerate()
                .map(|(i, title)| {
                    serde_json::json!({
                        "id": format!("focus-{i}"),
                        "title": title,
                        "description": ""
                    })
                })
                .collect();
            let response = run_bridge_action(
                "mission_put",
                serde_json::json!({
                    "mission": {
                        "statement": statement,
                        "targets": targets,
                        "profile": {
                            "whyThisMission": why,
                            "areasOfFocus": areas,
                        }
                    }
                }),
            );
            let ok = response
                .as_ref()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            let message = response
                .as_ref()
                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                .unwrap_or(if ok {
                    "Life Mission saved."
                } else {
                    "Could not save Life Mission."
                })
                .to_owned();
            let dialog = adw::AlertDialog::builder()
                .heading(if ok {
                    "Mission set"
                } else {
                    "Could not save"
                })
                .body(&message)
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            let on_saved = on_saved.clone();
            dialog.connect_response(None, move |_, _| {
                if ok {
                    on_saved();
                }
            });
            dialog.present(Some(&parent_for_cb));
        }),
    );
}

/// Shape Your Sovereign → soul_put structured fields; clears desktop chat session.
pub fn show_soul_interview(parent: &adw::ApplicationWindow, on_saved: Rc<dyn Fn()>) {
    let parent_for_cb = parent.clone();
    show_guided_interview(
        parent,
        "Shape Your Sovereign",
        "Answer a few questions. We will write your Sovereign’s Soul — the personality and rules that stay on this computer.",
        SOUL_QUESTIONS,
        Rc::new(move |answers| {
            let name = answers.get("name").cloned().unwrap_or_default();
            if name.trim().is_empty() || name.eq_ignore_ascii_case("centurion") {
                let fail = adw::AlertDialog::builder()
                    .heading("Name required")
                    .body("Choose a personal name for your Sovereign (for example Titus) before saving.")
                    .close_response("ok")
                    .build();
                fail.add_response("ok", "OK");
                fail.present(Some(&parent_for_cb));
                return;
            }
            let response = run_bridge_action(
                "soul_put",
                serde_json::json!({
                    "soul": {
                        "name": name.trim(),
                        "personalitySummary": answers.get("personalitySummary").cloned().unwrap_or_default(),
                        "tone": answers.get("tone").cloned().unwrap_or_default(),
                        "communicationStyle": answers.get("communicationStyle").cloned().unwrap_or_default(),
                        "responseLength": answers.get("responseLength").cloned().unwrap_or_default(),
                        "alwaysDo": answers.get("alwaysDo").cloned().unwrap_or_default(),
                        "neverDo": answers.get("neverDo").cloned().unwrap_or_default(),
                        "pushbackStyle": answers.get("pushbackStyle").cloned().unwrap_or_default(),
                        "uncertaintyStyle": answers.get("uncertaintyStyle").cloned().unwrap_or_default(),
                    }
                }),
            );
            let ok = response
                .as_ref()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            if ok {
                clear_desktop_chat_session();
            }
            let message = response
                .as_ref()
                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                .unwrap_or(if ok {
                    "Soul saved. Next Chat uses this identity."
                } else {
                    "Could not save Soul."
                })
                .to_owned();
            let dialog = adw::AlertDialog::builder()
                .heading(if ok { "Soul shaped" } else { "Could not save" })
                .body(&message)
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            let on_saved = on_saved.clone();
            dialog.connect_response(None, move |_, _| {
                if ok {
                    on_saved();
                }
            });
            dialog.present(Some(&parent_for_cb));
        }),
    );
}

/// Light About You interview → mission profile fields.
pub fn show_about_you_interview(parent: &adw::ApplicationWindow, on_saved: Rc<dyn Fn()>) {
    let parent_for_cb = parent.clone();
    show_guided_interview(
        parent,
        "About You",
        "Help your Sovereign know the human it partners with. This stays on this computer in your mission profile.",
        ABOUT_YOU_QUESTIONS,
        Rc::new(move |answers| {
            let response = run_bridge_action(
                "mission_put",
                serde_json::json!({
                    "mission": {
                        "profile": {
                            "yourStory": answers.get("yourStory").cloned().unwrap_or_default(),
                            "yourValues": answers.get("yourValues").cloned().unwrap_or_default(),
                            "workStyle": answers.get("workStyle").cloned().unwrap_or_default(),
                            "challenges": answers.get("challenges").cloned().unwrap_or_default(),
                        }
                    }
                }),
            );
            let ok = response
                .as_ref()
                .and_then(|p| p.get("ok").and_then(|v| v.as_bool()))
                .unwrap_or(false);
            let message = response
                .as_ref()
                .and_then(|p| p.get("message").and_then(|v| v.as_str()))
                .unwrap_or(if ok {
                    "Profile saved."
                } else {
                    "Could not save profile."
                })
                .to_owned();
            let dialog = adw::AlertDialog::builder()
                .heading(if ok { "About you saved" } else { "Could not save" })
                .body(&message)
                .close_response("ok")
                .build();
            dialog.add_response("ok", "OK");
            let on_saved = on_saved.clone();
            dialog.connect_response(None, move |_, _| {
                if ok {
                    on_saved();
                }
            });
            dialog.present(Some(&parent_for_cb));
        }),
    );
}

/// Privacy & Trust copy aligned with Adrian knowledge pillars (local brain, not cloud chat).
pub fn show_privacy_trust_dialog(parent: &adw::ApplicationWindow) {
    let body = "Your Centurion lives on this computer. Chat, Soul, mission, and memory stay here \
unless you choose to share something with support.\n\n\
• Private partnership — you remain the decision-maker; the Sovereign follows your mission and Soul.\n\
• Not a cloud chatbot — thinking may use an AI service you configure, but your desk Brain owns the relationship.\n\
• Optional iPhone remote — a thin convenience layer on the same Wi‑Fi; the desk is the product.\n\
• Adrian (support) is separate — cloud guidance that never reads your Crypto Chat unless you paste it.\n\n\
If something feels unsafe about AI in general: Centurion is built as a 1:1 companion under your oversight, \
not an autonomous agent that acts without you.";
    let dialog = adw::AlertDialog::builder()
        .heading("Privacy &amp; Trust")
        .body(body)
        .close_response("close")
        .build();
    dialog.add_response("close", "Close");
    dialog.present(Some(parent));
}
