module ReportBuilderHelper
  BUILDER_TABS = [
    ["columns", "Columns", "ti-columns"],
    ["related", "Related data", "ti-git-merge"],
    ["filters", "Filters", "ti-filter"],
    ["sort", "Sort", "ti-arrows-sort"],
    ["formulas", "Formulas", "ti-math-function"],
    ["delivery", "Delivery", "ti-calendar-event"]
  ].freeze

  KNOWN_OP_SUFFIXES = %w[eq not_eq cont not_cont in not_in gteq lteq gt lt null not_null].freeze

  # The settings tab to show: the one asked for, else the last one the user
  # opened (kept in a cookie by the builder JS, so a re-rendered panel stays on
  # the same tab), else Columns. Worked example H2.
  def builder_active_tab
    tab = params[:tab].presence || cookies[:rb_tab].presence
    BUILDER_TABS.any? { |key, _, _| key == tab } ? tab : "columns"
  end

  # "investor_name_cont" → { field: "investor_name", op: "cont" }
  def report_builder_parse_filter(pred_key)
    field, op = ReportBuilderFilterField.split_predicate(pred_key)
    { field: field, op: op || "eq" }
  end

  # Before related data is removed: which columns go with it, and that Undo
  # brings them back for 10 minutes. Worked example H13.
  def remove_join_summary(relation, column_labels)
    columns = column_labels.any? ? column_labels.to_sentence : "No columns"
    action_summary([
                     ["red", "ti-git-merge", "Removes #{relation.humanize.downcase}",
                      "Its filters, totals and pivot are removed from this report."],
                     ["amber", "ti-columns-off", "Removes #{pluralize(column_labels.size, 'column')}", columns],
                     ["grey", "ti-arrow-back-up", "Undo for 10 minutes", "Click Undo on the message that follows to put everything back."]
                   ])
  end

  # The report's filters as sentences, for wizard step 3 and the summary:
  # "Only include investors where Category is LP",
  # "Only capital commitments in Growth Fund II". Worked examples H23, H24.
  # → [{ text:, relation:, pred_key: }]
  def wizard_filter_sentences(config, entity)
    rows = config.root_filters.map { |pred_key, value| [nil, pred_key, value] } +
           config.joins.flat_map do |join|
             (join[:child_filters] || {}).map { |pred_key, value| [join[:relation].to_s, pred_key.to_s, value] }
           end

    rows.map do |relation, pred_key, value|
      subject = relation ? relation.humanize.downcase : wizard_model_label(config.root_model).pluralize.downcase
      text = if pred_key.to_s == "fund_id_eq"
               fund = Fund.where(entity_id: entity.id).find_by(id: value)
               "Only #{subject} in #{fund&.name || 'a fund that no longer exists'}"
             else
               words = ReportBuilderFilterField.describe(config: config, entity: entity, pred_key: pred_key, value: value, relation: relation)
               relation ? "Only #{subject} where #{words}" : "Only include #{subject} where #{words}"
             end
      { text: text, relation: relation, pred_key: pred_key.to_s }
    end
  end

  # The schedule's frequencies; weekly runs on Monday and monthly on the 1st
  # (ReportSchedule#run_on_day). Worked examples H4, E6 —
  # openspec/changes/report-builder-delivery/business-rules.md
  SCHEDULE_FREQUENCIES = { "daily" => "daily", "weekly" => "weekly on Monday", "monthly" => "monthly on the 1st" }.freeze

  # [["Daily at 09:00", "daily"], …] for the Frequency list
  def schedule_frequency_options(schedule)
    SCHEDULE_FREQUENCIES.map { |key, words| ["#{words.upcase_first} at #{schedule_run_at(schedule)}", key] }
  end

  # "IST" for Asia/Kolkata, "UTC" for UTC
  def report_schedule_zone(timezone)
    ActiveSupport::TimeZone[timezone.to_s]&.now&.strftime("%Z") || timezone.to_s
  end

  # "weekly on Monday at 09:00 IST" — for the save message and the popup (H4)
  def report_schedule_label(schedule)
    words = SCHEDULE_FREQUENCIES.fetch(schedule.frequency.to_s, schedule.frequency.to_s)
    "#{words} at #{schedule_run_at(schedule)} #{report_schedule_zone(schedule.timezone)}"
  end

  # "Last sent 02 Nov 2026 09:00 IST · Next 09 Nov 2026 09:00 IST", in the
  # schedule's own time zone; "Not sent yet" before the first send (H7, E7)
  def report_schedule_history(schedule)
    zone  = schedule.timezone.presence || "UTC"
    shown = ->(time) { "#{l(time.in_time_zone(zone), format: :abbr_date_time)} #{report_schedule_zone(zone)}" }
    last  = schedule.last_run_at ? "Last sent #{shown.call(schedule.last_run_at)}" : "Not sent yet"
    schedule.enabled && schedule.next_run_at ? "#{last} · Next #{shown.call(schedule.next_run_at)}" : last
  end

  # The Immediate Actions popup before saving a schedule that emails people
  # outside the company (H5, E3)
  def schedule_outsiders_summary(outsiders, entity, label)
    people = outsiders.one? ? "1 person" : "#{outsiders.size} people"
    action_summary([
                     ["red", "ti-mail-forward", "Emails #{people} outside #{entity.name}", outsiders.join(", ")],
                     ["grey", "ti-calendar-event", label.upcase_first, "Sends the full report as Excel, every time."]
                   ])
  end

  # Before an AI draft is discarded (report-builder-assistant E8)
  def discard_draft_summary
    action_summary([
                     ["red", "ti-trash", "Deletes this draft", "Its columns, filters, chart and the assistant's answers go."],
                     ["grey", "ti-arrow-back-up", "Can't be undone", "Describe the report again to start over."]
                   ])
  end

  # The report's chart: the suggested one rebuilt from these rows, a described
  # one (AgentChart), or nil. `default` is the kind when none was chosen yet
  # (the draft page suggests one; the report page shows none).
  # Worked examples H5, H7, H8 — openspec/changes/report-builder-assistant/business-rules.md
  def report_chart_for(report, config:, columns:, rows:, default: nil)
    choice = (report.template || {}).dig("chart", "kind") || default
    case choice
    when "suggested"
      ReportBuilderChartSuggestion.for(config: config, columns: columns, rows: rows)
    when "agent"
      chart = AgentChart.find_by(id: report.template.dig("chart", "agent_chart_id"), entity_id: report.entity_id)
      chart&.spec.present? ? { title: chart.title, spec: chart.spec, described: true } : nil
    end
  end

  private

  def schedule_run_at(schedule)
    schedule.run_at_time&.strftime("%H:%M") || "09:00"
  end

  # The Immediate Actions card list: [[tint, icon, title, description]]
  def action_summary(cards)
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
