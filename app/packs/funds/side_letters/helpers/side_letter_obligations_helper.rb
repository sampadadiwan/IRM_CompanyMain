# View helpers for the LP Obligation Matrix.
module SideLetterObligationsHelper
  # One badge that answers "where does this obligation stand?" — review state
  # first (pending/rejected), then lifecycle for approved rows. Every badge
  # carries a tooltip (needs a data-controller="tooltip" ancestor) because the
  # states are the hardest part of this feature for users to internalise.
  def obligation_status_badge(obligation)
    if obligation.pending_review?
      obligation_badge_tag("Pending review", "bg-warning text-dark",
                           "Waiting for counsel to approve or reject. Nothing is tracked and no alerts are sent until approval.")
    elsif obligation.rejected?
      obligation_badge_tag("Rejected", "bg-secondary",
                           "Counsel rejected this obligation — it will never create tasks or alerts.")
    elsif obligation.armed?
      obligation_badge_tag("Armed", "bg-info text-dark",
                           "Event-triggered: there is no due date until the event happens. Use Fire to set a deadline when it does.")
    elsif obligation.obligation_active?
      obligation_due_badge(obligation)
    elsif obligation.status.to_s == "waived"
      obligation_badge_tag("Waived", "bg-secondary",
                           "Counsel ended this obligation. Open tasks were removed; completed history is preserved. Use Revert if this was a mistake.")
    elsif obligation.status.to_s == "fulfilled"
      obligation_badge_tag("Fulfilled", "bg-success",
                           "The obligation was completed — see the fulfillment history for the audit trail.")
    else
      obligation_badge_tag(obligation.status.to_s.humanize, "bg-secondary", nil)
    end
  end

  def obligation_type_options
    SideLetterObligation.obligation_types.keys.map { |k| [k.humanize, k] }
  end

  def trigger_type_options
    SideLetterObligation.trigger_types.keys.map { |k| [k.humanize, k] }
  end

  def owner_team_options
    SideLetterObligation::OWNER_TEAMS.map { |k| [k.humanize, k] }
  end

  # @return [String] Compact badge showing the LLM-assigned legal classification.
  #   CP (blue) = condition precedent, CS (teal) = condition subsequent,
  #   SLO (grey) = standard side-letter obligation (default).
  def legal_category_badge(obligation)
    case obligation.legal_category
    when "condition_precedent"
      obligation_badge_tag("CP", "bg-primary",
                           "Condition Precedent — must be satisfied before the relevant event or closing")
    when "condition_subsequent"
      obligation_badge_tag("CS", "bg-info text-dark",
                           "Condition Subsequent — ongoing obligation with breach consequences")
    else
      obligation_badge_tag("SLO", "bg-secondary",
                           "Side Letter Obligation — standard promise or covenant")
    end
  end

  # @return [Array<Array(String, String)>] Options for the legal_category filter dropdown.
  def legal_category_options
    SideLetterObligation.legal_categories.keys.map { |k| [k.humanize, k] }
  end

  private

  # Active + dated: show urgency relative to the nearest open task.
  # Private (and obligation-prefixed) because Rails mixes every helper module
  # into every view — a generic name here silently overrides same-named helpers
  # in other packs (this collided with DealInvestorsHelper#status_badge).
  def obligation_due_badge(obligation)
    due = obligation.tasks.incomplete.where.not(due_date: nil).minimum(:due_date) || obligation.next_due_date
    return obligation_badge_tag("Active", "bg-success", "Approved and tracked — tasks and due-date alerts are live.") if due.blank?

    days = (due - Time.zone.today).to_i
    if days.negative?
      obligation_badge_tag("Overdue #{days.abs}d", "bg-danger",
                           "The nearest task slipped its due date #{days.abs} day(s) ago. The owner is re-alerted on the escalation cadence.")
    elsif days.zero?
      obligation_badge_tag("Due today", "bg-danger", "The nearest task is due today — the owner has been alerted.")
    elsif days <= 14
      obligation_badge_tag("Due in #{days}d", "bg-warning text-dark",
                           "The nearest open task is due on #{due.strftime('%d %b %Y')}. The owner is reminded ahead of time per the obligation's lead-time setting.")
    else
      obligation_badge_tag("Active", "bg-success",
                           "Approved and tracked — next task due #{due.strftime('%d %b %Y')}.")
    end
  end

  # Renders one badge span; attaches a Bootstrap tooltip only when a tip is given.
  def obligation_badge_tag(label, css, tip)
    options = { class: "badge #{css}" }
    options.merge!(title: tip, data: { bs_toggle: "tooltip" }) if tip
    tag.span(label, **options)
  end
end
