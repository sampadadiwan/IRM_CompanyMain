# Compliance screens reuse the app's own building blocks (stats cards, subtle badges, info tooltips,
# explainer alerts). This helper only names them once so every compliance page uses the same icon and
# colour for the same concept (R110). Theme colours only: success / info / danger / secondary.
module ComplianceUiHelper
  # One Tabler icon per concept, used on every page, tab, button and badge
  CMP_ICONS = {
    compliance: "ti-shield-check", register: "ti-alert-triangle", duty: "ti-checklist", fact: "ti-file-text",
    pack: "ti-book", version: "ti-versions", fund_pack: "ti-link", setup: "ti-settings", result: "ti-calculator",
    run: "ti-player-play", ai: "ti-sparkles", approve: "ti-check", reject: "ti-x", assign: "ti-user-plus",
    explain: "ti-message-2", view: "ti-eye", download: "ti-download", publish: "ti-send", save: "ti-device-floppy",
    overdue: "ti-clock-exclamation", fund: "ti-building-bank", upload: "ti-upload", history: "ti-history",
    new: "ti-plus", read: "ti-scan", calendar: "ti-calendar", user: "ti-user", filter: "ti-filter",
    pass: "ti-circle-check", breach: "ti-alert-triangle", needs_review: "ti-eye-search",
    could_not_check: "ti-help-circle", warning: "ti-alert-circle", lock: "ti-lock", done: "ti-circle-check",
    edit: "ti-edit", json: "ti-code"
  }.freeze

  # Outcome of one check — "Could not check" is never green (R5)
  CMP_OUTCOMES = {
    "pass" => %w[Pass success], "breach" => %w[Breach danger], "warning" => ["Warning — in transition", "info"],
    "needs_review" => ["Needs review", "info"], "could_not_check" => ["Could not check", "secondary"]
  }.freeze

  CMP_ITEM_STATUSES = {
    "open" => %w[Open danger], "in_progress" => ["In progress", "info"], "pending_approval" => ["Pending approval", "info"],
    "explained" => %w[Explained secondary], "closed" => %w[Closed success]
  }.freeze

  CMP_DUTY_STATES = {
    "overdue" => ["Overdue", "danger", :overdue], "due" => ["Due", "info", :calendar],
    "scheduled" => ["Scheduled", "secondary", :calendar], "done" => ["Done", "success", :done]
  }.freeze

  def cmp_icon(key, extra = "me-1")
    tag.i(class: "ti #{CMP_ICONS.fetch(key)} #{extra}".strip)
  end

  # The info-circle tooltip used next to labels and column headers (capital_calls/_common_form_fields)
  def cmp_tip(text)
    tag.i(class: "ti ti-info-circle text-muted ms-1", data: { bs_toggle: "tooltip", bs_placement: "top", bs_title: text },
          aria: { label: text })
  end

  # badge bg-X-subtle text-X with a leading icon (the app's status badge style)
  def cmp_badge(label, colour, icon = nil, id: nil, title: nil)
    data = title ? { bs_toggle: "tooltip", bs_title: title } : {}
    tag.span(class: "badge bg-#{colour}-subtle text-#{colour}", id:, data:) do
      safe_join([icon ? cmp_icon(icon) : nil, label].compact)
    end
  end

  def cmp_outcome_badge(outcome)
    label, colour = CMP_OUTCOMES[outcome.to_s] || [outcome.to_s.humanize, "secondary"]
    cmp_badge(label, colour, CMP_ICONS.key?(outcome.to_s.to_sym) ? outcome.to_s.to_sym : nil)
  end

  # Register item status; closed items show why they closed ("Cleared by data")
  def cmp_item_status_badge(item)
    return cmp_badge(item.closed_label || "Closed", "success", :done) if item.closed?

    label, colour = CMP_ITEM_STATUSES[item.status] || [item.status.humanize, "secondary"]
    cmp_badge(label, colour, :register)
  end

  def cmp_duty_badge(duty)
    state = duty.state
    label, colour, icon = CMP_DUTY_STATES[state] || [state.humanize, "secondary", :calendar]
    label = "#{label} — late (#{duty.late_days} days)" if duty.done? && duty.late_days.positive?
    cmp_badge(label, colour, icon)
  end

  # One short "what this page is for / what to do next" line (capital_calls/_form explainer)
  def cmp_explainer(text, id: nil)
    tag.div(class: "alert alert-info d-flex align-items-start gap-2", id:) do
      safe_join([tag.i(class: "ti ti-info-circle fs-5 flex-shrink-0"), tag.div(text)])
    end
  end

  # A row of the app's NumberStatsComponent cards (capital_calls/_grid_stats)
  def cmp_stats(cards, id:)
    tag.div(class: "row mb-3", id:) do
      safe_join(cards.map do |c|
        render(NumberStatsComponent.new(path: c[:path], amount: c[:stat].to_s, subtitle: c[:subtitle],
                                        progress_bar_color: c[:colour], text_info: CMP_ICONS.fetch(c[:icon]).delete_prefix("ti-"),
                                        tooltip: c[:tooltip], fs_size: 4))
      end)
    end
  end

  # Header button with a leading icon (capital_calls/_index header buttons)
  def cmp_header_link(label, path, icon:, colour: "primary", **)
    link_to(path, class: "btn btn-outline-#{colour} d-inline-flex align-items-center", **) do
      safe_join([cmp_icon(icon), label])
    end
  end

  def cmp_applicability(version)
    case version.applicability
    when "new_funds" then "New funds only#{" (started on or after #{l(version.applicability_date)})" if version.applicability_date}"
    when "transition" then "All funds, transition until #{version.transition_ends_on ? l(version.transition_ends_on) : '—'}"
    else "All funds"
    end
  end
end
