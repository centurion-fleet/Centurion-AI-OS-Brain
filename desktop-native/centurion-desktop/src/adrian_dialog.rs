//! GTK chat surface for Adrian on the Linux desktop.

use adw::prelude::*;
use gtk4 as gtk;
use libadwaita as adw;
use std::cell::RefCell;
use std::rc::Rc;

use crate::adrian::{self, AdrianMessage, AdrianRole, SuggestedAction};

pub struct AdrianDialogHooks {
    pub build_context: Rc<dyn Fn() -> adrian::AdrianChatContext>,
    pub on_action: Rc<dyn Fn(&str)>,
}

impl Clone for AdrianDialogHooks {
    fn clone(&self) -> Self {
        Self {
            build_context: self.build_context.clone(),
            on_action: self.on_action.clone(),
        }
    }
}

pub fn show_adrian_dialog(parent: &adw::ApplicationWindow, hooks: AdrianDialogHooks) {
    let dialog = adw::Dialog::builder()
        .content_width(520)
        .content_height(640)
        .follows_content_size(false)
        .build();

    let messages: Rc<RefCell<Vec<AdrianMessage>>> = Rc::new(RefCell::new(Vec::new()));
    let suggested: Rc<RefCell<Vec<SuggestedAction>>> = Rc::new(RefCell::new(Vec::new()));
    let last_error: Rc<RefCell<Option<String>>> = Rc::new(RefCell::new(None));
    let is_sending: Rc<RefCell<bool>> = Rc::new(RefCell::new(false));
    let privacy_accepted = Rc::new(RefCell::new(adrian::has_accepted_privacy()));

    let stack = gtk::Stack::new();
    stack.set_vexpand(true);
    stack.set_transition_type(gtk::StackTransitionType::Crossfade);
    stack.set_transition_duration(180);

    let (privacy_page, continue_button) = build_privacy_page();
    let chat_page = gtk::Box::new(gtk::Orientation::Vertical, 0);
    chat_page.set_vexpand(true);

    stack.add_named(&privacy_page, Some("privacy"));
    stack.add_named(&chat_page, Some("chat"));

    if *privacy_accepted.borrow() {
        stack.set_visible_child_name("chat");
        adrian::seed_welcome(&mut messages.borrow_mut());
    } else {
        stack.set_visible_child_name("privacy");
    }

    let message_list = gtk::ListBox::new();
    message_list.set_selection_mode(gtk::SelectionMode::None);
    message_list.add_css_class("boxed-list");
    message_list.set_margin_top(8);
    message_list.set_margin_bottom(8);
    message_list.set_margin_start(12);
    message_list.set_margin_end(12);

    let message_scroll = gtk::ScrolledWindow::builder()
        .vexpand(true)
        .hexpand(true)
        .min_content_height(320)
        .build();
    message_scroll.set_child(Some(&message_list));

    let chips_box = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    chips_box.set_margin_start(12);
    chips_box.set_margin_end(12);
    chips_box.set_margin_bottom(4);
    chips_box.set_wrap(true);
    chips_box.set_homogeneous(false);

    let error_label = gtk::Label::builder()
        .wrap(true)
        .xalign(0.0)
        .margin_start(12)
        .margin_end(12)
        .margin_bottom(4)
        .css_classes(["error"])
        .build();
    error_label.set_visible(false);

    let input_row = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    input_row.set_margin_start(12);
    input_row.set_margin_end(12);
    input_row.set_margin_top(8);
    input_row.set_margin_bottom(12);

    let input = gtk::Entry::builder()
        .placeholder_text("Ask Adrian for help…")
        .hexpand(true)
        .build();
    let send_button = gtk::Button::from_icon_name("mail-send-symbolic");
    send_button.add_css_class("suggested-action");
    send_button.set_tooltip_text(Some("Send"));
    let sending_spinner = gtk::Spinner::new();
    sending_spinner.set_visible(false);

    input_row.append(&input);
    input_row.append(&send_button);
    input_row.append(&sending_spinner);

    chat_page.append(&message_scroll);
    chat_page.append(&chips_box);
    chat_page.append(&error_label);
    chat_page.append(&input_row);

    let toolbar = adw::ToolbarView::new();
    let header = adw::HeaderBar::new();
    header.set_title_widget(Some(
        &gtk::Label::builder()
            .label("Adrian")
            .css_classes(["title"])
            .build(),
    ));
    let close_button = gtk::Button::from_icon_name("window-close-symbolic");
    close_button.set_tooltip_text(Some("Close"));
    let dialog_for_close = dialog.clone();
    close_button.connect_clicked(move |_| dialog_for_close.close());
    header.pack_end(&close_button);
    toolbar.add_top_bar(&header);
    toolbar.set_content(Some(&stack));
    dialog.set_child(Some(&toolbar));

    let refresh_messages: Rc<dyn Fn()> = Rc::new({
        let message_list = message_list.clone();
        let messages = messages.clone();
        move || {
            while let Some(child) = message_list.first_child() {
                message_list.remove(&child);
            }
            for message in messages.borrow().iter() {
                message_list.append(&message_row(message));
            }
            if let Some(last) = message_list.last_child() {
                message_list.select_row(
                    last.downcast_ref::<gtk::ListBoxRow>().expect("message row"),
                );
            }
        }
    });

    let refresh_chips: Rc<dyn Fn()> = Rc::new({
        let chips_box = chips_box.clone();
        let suggested = suggested.clone();
        let on_action = hooks.on_action.clone();
        move || {
            while let Some(child) = chips_box.first_child() {
                chips_box.remove(&child);
            }
            for action in suggested.borrow().iter() {
                let button = gtk::Button::with_label(&action.label);
                button.add_css_class("pill");
                let action_id = action.id.clone();
                let handler = on_action.clone();
                button.connect_clicked(move |_| handler(&action_id));
                chips_box.append(&button);
            }
            chips_box.set_visible(!suggested.borrow().is_empty());
        }
    });

    let set_error: Rc<dyn Fn(Option<String>)> = Rc::new({
        let error_label = error_label.clone();
        let last_error = last_error.clone();
        move |text: Option<String>| {
            *last_error.borrow_mut() = text.clone();
            if let Some(message) = text {
                error_label.set_label(&message);
                error_label.set_visible(true);
            } else {
                error_label.set_visible(false);
            }
        }
    });

    let set_sending: Rc<dyn Fn(bool)> = Rc::new({
        let send_button = send_button.clone();
        let sending_spinner = sending_spinner.clone();
        let input = input.clone();
        let is_sending = is_sending.clone();
        move |sending: bool| {
            *is_sending.borrow_mut() = sending;
            send_button.set_visible(!sending);
            sending_spinner.set_visible(sending);
            if sending {
                sending_spinner.start();
            } else {
                sending_spinner.stop();
            }
            input.set_sensitive(!sending);
        }
    });

    {
        let privacy_accepted = privacy_accepted.clone();
        let stack = stack.clone();
        let messages = messages.clone();
        let refresh_messages = refresh_messages.clone();
        continue_button.connect_clicked(move |_| {
            adrian::accept_privacy();
            *privacy_accepted.borrow_mut() = true;
            adrian::seed_welcome(&mut messages.borrow_mut());
            refresh_messages();
            stack.set_visible_child_name("chat");
        });
    }

    refresh_messages();
    refresh_chips();

    let submit: Rc<dyn Fn()> = Rc::new({
        let messages = messages.clone();
        let suggested = suggested.clone();
        let hooks = hooks.clone();
        let input = input.clone();
        let refresh_messages = refresh_messages.clone();
        let refresh_chips = refresh_chips.clone();
        let set_error = set_error.clone();
        let set_sending = set_sending.clone();
        let is_sending = is_sending.clone();
        let privacy_accepted = privacy_accepted.clone();
        move || {
            if *is_sending.borrow() || !*privacy_accepted.borrow() {
                return;
            }
            let text = input.text().to_string();
            if text.trim().is_empty() {
                return;
            }
            input.set_text("");
            messages.borrow_mut().push(AdrianMessage {
                role: AdrianRole::User,
                content: text.clone(),
            });
            refresh_messages();
            set_error(None);
            set_sending(true);

            let context = (hooks.build_context)();
            let history = messages.borrow().clone();
            let messages = messages.clone();
            let suggested = suggested.clone();
            let refresh_messages = refresh_messages.clone();
            let refresh_chips = refresh_chips.clone();
            let set_error = set_error.clone();
            let set_sending = set_sending.clone();
            std::thread::spawn(move || {
                let result = adrian::send_chat(&history, &text, &context);
                glib::idle_add_local(move || {
                    set_sending(false);
                    match result {
                        Ok(response) if response.ok => {
                            messages.borrow_mut().push(AdrianMessage {
                                role: AdrianRole::Adrian,
                                content: response.reply,
                            });
                            *suggested.borrow_mut() = response.suggested_actions;
                            refresh_messages();
                            refresh_chips();
                        }
                        Ok(response) => {
                            let message = if response.message.is_empty() {
                                "Adrian couldn't respond right now.".to_owned()
                            } else {
                                response.message
                            };
                            set_error(Some(message));
                        }
                        Err(error) => set_error(Some(error)),
                    }
                    glib::ControlFlow::Remove
                });
            });
        }
    });

    send_button.connect_clicked({
        let submit = submit.clone();
        move |_| submit()
    });
    input.connect_activate({
        let submit = submit.clone();
        move |_| submit()
    });

    dialog.present(Some(parent));
}

fn build_privacy_page() -> (gtk::Box, gtk::Button) {
    let page = gtk::Box::new(gtk::Orientation::Vertical, 16);
    page.set_margin_top(24);
    page.set_margin_bottom(24);
    page.set_margin_start(24);
    page.set_margin_end(24);
    page.set_vexpand(true);
    page.set_valign(gtk::Align::Center);

    page.append(
        &gtk::Label::builder()
            .label("Meet Adrian")
            .css_classes(["title-2"])
            .xalign(0.0)
            .build(),
    );
    page.append(
        &gtk::Label::builder()
            .label(
                "Adrian online is Adrian who created Centurion. His passion is helping you live \
                 your mission — lift daily pressure, free your thinking, and deepen your \
                 1:1 relationship with your private Centurion. Missions evolve; that's expected.",
            )
            .wrap(true)
            .xalign(0.0)
            .build(),
    );
    page.append(
        &gtk::Label::builder()
            .label(
                "Adrian listens first, then helps one step at a time. He works over the internet, \
                 separate from your private Centurion link, and sees only what helps — link status, \
                 thinking health in plain words, and a short mission summary if you've set one. \
                 Never your chat history or secrets.",
            )
            .wrap(true)
            .xalign(0.0)
            .css_classes(["dim-label"])
            .build(),
    );

    let continue_button = gtk::Button::with_label("Continue with Adrian");
    continue_button.add_css_class("suggested-action");
    continue_button.set_halign(gtk::Align::Center);
    continue_button.set_size_request(-1, 44);
    page.append(&continue_button);

    (page, continue_button)
}

fn message_row(message: &AdrianMessage) -> gtk::ListBoxRow {
    let row = gtk::ListBoxRow::new();
    row.set_selectable(false);
    row.set_activatable(false);

    let outer = gtk::Box::new(gtk::Orientation::Horizontal, 8);
    outer.set_margin_top(6);
    outer.set_margin_bottom(6);

    let bubble = gtk::Box::new(gtk::Orientation::Vertical, 4);
    bubble.set_hexpand(true);

    if message.role == AdrianRole::Adrian {
        bubble.append(
            &gtk::Label::builder()
                .label("Adrian")
                .css_classes(["caption", "accent"])
                .xalign(0.0)
                .build(),
        );
    }

    bubble.append(
        &gtk::Label::builder()
            .label(&message.content)
            .wrap(true)
            .xalign(if message.role == AdrianRole::User {
                1.0
            } else {
                0.0
            })
            .justify(gtk::Justification::Left)
            .build(),
    );

    if message.role == AdrianRole::User {
        let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        outer.append(&spacer);
        bubble.set_halign(gtk::Align::End);
        bubble.add_css_class("centurion-adrian-user");
        outer.append(&bubble);
    } else {
        bubble.set_halign(gtk::Align::Start);
        bubble.add_css_class("centurion-adrian-bot");
        outer.append(&bubble);
        let spacer = gtk::Box::new(gtk::Orientation::Horizontal, 0);
        spacer.set_hexpand(true);
        outer.append(&spacer);
    }

    row.set_child(Some(&outer));
    row
}
