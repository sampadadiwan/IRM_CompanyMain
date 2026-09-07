# View helpers for the allocation run templates screens: status badges and the short
# "what this template does" summary shown in lists, pre-flight and progress pages.
module AllocationRunTemplatesHelper
  # Badge classes per group run status (theme colours only — see feedback on badges).
  GROUP_RUN_STATUS_BADGE = {
    "queued" => ["bg-secondary-subtle text-secondary", "ti-clock", "Queued", "Waiting for a worker to pick it up"],
    "running" => ["bg-primary-subtle text-primary", "ti-loader", "Running", "Templates are running one after another"],
    "success" => ["bg-success-subtle text-success", "ti-circle-check", "Success", "Every template finished with status Success"],
    "failed" => ["bg-danger-subtle text-danger", "ti-alert-triangle", "Failed", "A template failed; the ones after it were skipped"]
  }.freeze

  ITEM_STATUS_BADGE = {
    "pending" => ["bg-secondary-subtle text-secondary", "ti-clock", "Pending", "Not started yet"],
    "running" => ["bg-primary-subtle text-primary", "ti-loader", "Running", "The allocation engine is on this template now"],
    "success" => ["bg-success-subtle text-success", "ti-circle-check", "Success", "The allocation run finished with status Success"],
    "failed" => ["bg-danger-subtle text-danger", "ti-alert-triangle", "Failed", "The run did not finish with status Success; the group stopped here"],
    "skipped" => ["bg-warning-subtle text-warning", "ti-player-skip-forward", "Skipped", "Not run because an earlier template failed"],
    "reused" => ["bg-info-subtle text-info", "ti-history", "Reused", "Kept the success from an earlier run for this period"]
  }.freeze

  CHECK_STATUS_BADGE = {
    ready: ["bg-success-subtle text-success", "ti-circle-check", "Ready", "All checks passed"],
    warning: ["bg-warning-subtle text-warning", "ti-alert-circle", "Warnings", "Will run, but read the warnings first"],
    blocked: ["bg-danger-subtle text-danger", "ti-ban", "Blocked", "Would be refused — nothing in the group runs until this is fixed"],
    reused: ["bg-info-subtle text-info", "ti-history", "Already done", "Succeeded in the previous run for this period; will be skipped"]
  }.freeze

  def group_run_status_badge(status)
    art_status_badge(GROUP_RUN_STATUS_BADGE[status.to_s] || ["bg-secondary-subtle text-secondary", "ti-help", status.to_s.humanize, ""])
  end

  def group_run_item_status_badge(status)
    art_status_badge(ITEM_STATUS_BADGE[status.to_s] || ["bg-secondary-subtle text-secondary", "ti-help", status.to_s.humanize, ""])
  end

  def preflight_check_badge(status)
    art_status_badge(CHECK_STATUS_BADGE[status.to_sym] || ["bg-secondary-subtle text-secondary", "ti-help", status.to_s.humanize, ""])
  end

  # Small badges describing what a template does, each with a tooltip explaining the option.
  def template_option_badges(template)
    badges = []
    if template.run_allocations?
      badges << ["bg-primary-subtle text-primary", "ti-function", "Formulas: #{template.scope_label}",
                 "Runs the fund's allocation formulas. Scope: #{template.scope_label == 'Both' ? 'Accounting and Reporting formulas' : "#{template.scope_label} formulas only"}."]
      template.tags.each do |tag|
        badges << ["bg-secondary-subtle text-secondary", "ti-tag", tag, "Only formulas tagged \"#{tag}\" are run."]
      end
    end
    if template.generate_soa?
      badges << ["bg-success-subtle text-success", "ti-file-text", "Statements: #{template.statement_for}",
                 "Generates an investor statement per #{template.statement_for.to_s.downcase} using \"#{template.statement_document&.name || 'missing document'}\"."]
    end
    badges << ["bg-info-subtle text-info", "ti-chart-bar", "Fund ratios", "Generates fund ratios after the allocation finishes."] if template.fund_ratios?
    badges << ["bg-warning-subtle text-warning", "ti-bug", "Explain", "Records how each formula was evaluated, for debugging."] if template.explain?
    badges << ["bg-danger-subtle text-danger", "ti-flask", "Sample", "Runs on a few folios only. Not for a real close."] if template.sample?

    safe_join(badges.map do |css, icon, label, tip|
      content_tag(:span, class: "badge #{css} me-1 mb-1", data: { bs_toggle: "tooltip" }, title: tip) do
        safe_join([content_tag(:i, "", class: "ti #{icon} me-1"), label])
      end
    end)
  end

  # "3 min 12 s" style duration for progress rows.
  def format_run_duration(seconds)
    return "—" if seconds.nil?

    total = seconds.to_i
    return "#{total} s" if total < 60

    minutes, secs = total.divmod(60)
    return "#{minutes} min #{secs} s" if minutes < 60

    hours, minutes = minutes.divmod(60)
    "#{hours} h #{minutes} min"
  end

  private

  def art_status_badge((css, icon, label, tip))
    content_tag(:span, class: "badge #{css}", data: { bs_toggle: "tooltip" }, title: tip) do
      safe_join([content_tag(:i, "", class: "ti #{icon} me-1"), label])
    end
  end
end
