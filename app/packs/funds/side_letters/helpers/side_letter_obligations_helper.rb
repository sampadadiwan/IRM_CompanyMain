# View helpers for the LP Obligation Matrix.
module SideLetterObligationsHelper
  # One badge that answers "where does this obligation stand?" — review state
  # first (pending/rejected), then lifecycle for approved rows. Every badge
  # carries a tooltip (needs a data-controller="tooltip" ancestor) because the
  # states are the hardest part of this feature for users to internalise.
  def obligation_status_badge(obligation)
    if obligation.pending_review?
      status_badge("Pending review", "bg-warning text-dark",
                   "Waiting for counsel to approve or reject. Nothing is tracked and no alerts are sent until approval.")
    elsif obligation.rejected?
      status_badge("Rejected", "bg-secondary",
                   "Counsel rejected this obligation — it will never create tasks or alerts.")
    elsif obligation.armed?
      status_badge("Armed", "bg-info text-dark",
                   "Event-triggered: there is no due date until the event happens. Use Fire to set a deadline when it does.")
    elsif obligation.obligation_active?
      due_badge(obligation)
    elsif obligation.status.to_s == "waived"
      status_badge("Waived", "bg-secondary",
                   "Counsel ended this obligation. Open tasks were removed; completed history is preserved. Use Revert if this was a mistake.")
    elsif obligation.status.to_s == "fulfilled"
      status_badge("Fulfilled", "bg-success",
                   "The obligation was completed — see the fulfillment history for the audit trail.")
    else
      status_badge(obligation.status.to_s.humanize, "bg-secondary", nil)
    end
  end

  # Active + dated: show urgency relative to the nearest open task
  def due_badge(obligation)
    due = obligation.tasks.incomplete.where.not(due_date: nil).minimum(:due_date) || obligation.next_due_date
    return status_badge("Active", "bg-success", "Approved and tracked — tasks and due-date alerts are live.") if due.blank?

    days = (due - Time.zone.today).to_i
    if days.negative?
      status_badge("Overdue #{days.abs}d", "bg-danger",
                   "The nearest task slipped its due date #{days.abs} day(s) ago. The owner is re-alerted on the escalation cadence.")
    elsif days.zero?
      status_badge("Due today", "bg-danger", "The nearest task is due today — the owner has been alerted.")
    elsif days <= 14
      status_badge("Due in #{days}d", "bg-warning text-dark",
                   "The nearest open task is due on #{due.strftime('%d %b %Y')}. The owner is reminded ahead of time per the obligation's lead-time setting.")
    else
      status_badge("Active", "bg-success",
                   "Approved and tracked — next task due #{due.strftime('%d %b %Y')}.")
    end
  end

  def status_badge(label, css, tip)
    options = { class: "badge #{css}" }
    options.merge!(title: tip, data: { bs_toggle: "tooltip" }) if tip
    tag.span(label, **options)
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
end
