# frozen_string_literal: true

# ⑥ The words the call and distribution pages use for maker–checker (OWASP review 2026-11 M13, design card ⑥,
# task U.1: every control says why, what it means and what to do). One place, so the page, the popup and the
# Cucumber assertions use the same sentences.
module MakerCheckerHelper
  # "call" / "distribution"
  def maker_checker_noun(record)
    record.is_a?(CapitalDistribution) ? "distribution" : "call"
  end

  # H13 / E28 — the tooltip on the disabled Approve item
  def maker_checker_approve_disabled_reason(record)
    "You prepared this #{maker_checker_noun(record)}, so another approver must approve it (maker–checker is on). " \
      "Use Request approval to ask them."
  end

  # H15 — the ⓘ beside "Prepared by": what the row means and why it matters
  def maker_checker_prepared_by_tooltip(record)
    noun = maker_checker_noun(record)
    children = record.is_a?(CapitalDistribution) ? "payments" : "remittances"
    text = "People who created, imported or changed this #{noun}'s figures (or its #{children}' or fee lines' figures). " \
           "Editing the name, notes or custom fields, or recording payments, doesn't count."
    if record.maker_checker_on?
      "#{text} Your firm requires a second person to approve, so none of them can approve this #{noun}."
    else
      "#{text} Your firm lets the preparer approve; a self-approval is labelled \"also prepared it\"."
    end
  end

  # H14 / H17 — the ⓘ on the self-approval label
  def maker_checker_self_approval_tooltip(record)
    "#{record.approved_by_user&.full_name} approved this #{maker_checker_noun(record)} and also prepared it. Your firm " \
      "allows this because maker–checker is off (Settings › Entity › Approvals)."
  end

  # H18 / E34 — the Request approval popup: what happens when they click Proceed, in the "Immediate Actions" cards
  # (action_summary_modal.scss; the KYC Request Updates popup's look). Tints blue / amber / green, red when nobody
  # can approve.
  def maker_checker_action_summary(record, checkers, user)
    noun = maker_checker_noun(record)
    preparer_names = record.preparers.map(&:full_name).to_sentence
    cards = []
    cards << if checkers.any?
               [:blue, "ti-mail", "#{checkers.map(&:full_name).to_sentence} #{checkers.size == 1 ? 'is' : 'are'} emailed",
                "A bell alert and an email link them to this #{noun}. They can't be asked again for an hour."]
             else
               # E34 — said before the click, not only after it
               [:red, "ti-alert-triangle", "No one else can approve this #{noun} yet",
                "Nothing will be sent. Ask a company admin to give the Approver role to a colleague with access to " \
                "this fund, or turn off maker–checker in Settings."]
             end
    own = record.preparer_ids.include?(user.id) ? "You prepared it" : "Only an approver who didn't prepare it can approve it"
    cards << [:amber, "ti-user-exclamation", "You can't approve it yourself",
              "#{own}#{" (prepared by #{preparer_names})" if preparer_names.present?}."]
    cards << [:green, "ti-circle-check", "Nothing else changes",
              "The #{noun} stays unapproved and no investor is emailed."]
    maker_checker_summary_markup(cards).to_str
  end

  private

  # The "Immediate Actions" intro and one tinted card per [tint, icon, title, description]
  def maker_checker_summary_markup(cards)
    intro = tag.div(class: "action-summary__intro") do
      tag.div("Immediate Actions", class: "fw-bold text-dark") +
        tag.div(safe_join(["The following will happen when you click ", tag.strong("Proceed"), ":"]), class: "text-muted")
    end
    items = cards.map do |tint, icon, title, desc|
      tag.div(class: "action-summary__item action-summary__item--#{tint}") do
        tag.span(tag.i(class: "ti #{icon}"), class: "action-summary__icon") +
          tag.div(tag.div(title, class: "action-summary__title") + tag.div(desc, class: "action-summary__desc"))
      end
    end
    intro + tag.div(safe_join(items), class: "action-summary__list")
  end
end
