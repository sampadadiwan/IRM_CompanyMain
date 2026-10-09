# View helpers for Document Checks: dom ids, dropdown options, and the one place an outcome code becomes
# the sentence users read (config/locales/doc_checks.en.yml).
# See openspec/changes/document-checks/design.md (card ⑥ Judge — outcome codes → sentence → actions).
module DocChecksHelper
  def doc_check_card_dom_id(document_name)
    "doc_check_card_#{document_name.to_s.parameterize(separator: '_').presence || 'blank'}"
  end

  def doc_check_panel_frame_id(record)
    DocChecks::Broadcast.panel_frame_id(record)
  end

  # Tabler icon per kind of check
  DOC_CHECK_ACTION_ICONS = { "fill_in" => "ti-pencil", "compare" => "ti-arrows-left-right", "question" => "ti-help-circle" }.freeze

  def doc_check_action_icon(action)
    DOC_CHECK_ACTION_ICONS.fetch(action.to_s, "ti-checks")
  end

  # Tabler icon for a document, guessed from its name (purely visual)
  DOC_CHECK_DOCUMENT_ICONS = [
    [/\bpan\b|aadh?aa?r|\bid\b|identity|\bpoi\b/i, "ti-id"],
    [/passport/i, "ti-world"],
    [/address|utility|\bpoa\b/i, "ti-home"],
    [/\bcml\b|bank|cheque|statement|demat/i, "ti-building-bank"],
    [/incorporation|company|\bcoi\b|board|resolution|gst|moa|aoa/i, "ti-building"],
    [/director|beneficial|owner|shareholder/i, "ti-users"],
    [/signator|signature|declaration/i, "ti-signature"],
    [/fatca|crs|tax/i, "ti-receipt-tax"]
  ].freeze

  def doc_check_document_icon(document_name)
    DOC_CHECK_DOCUMENT_ICONS.find { |pattern, _| document_name.to_s.match?(pattern) }&.last || "ti-file-text"
  end

  # What a document's checks do, in plain words, for its tile: one line per kind, field labels joined,
  # long lists shortened ("Fills DP ID, Client ID +4"). Worked example E1.
  def doc_check_summary_lines(rows, fields)
    labels = fields.index_by(&:name)
    rows.group_by(&:action).sort_by { |action, _| DocCheck::ACTIONS.index(action) || 9 }.map do |action, list|
      names = list.map { |row| action == "question" ? row.look_for : (labels[row.field_name]&.label || row.look_for) }
      shown = names.first(3).join(", ")
      shown += " +#{names.size - 3}" if names.size > 3
      [doc_check_action_icon(action), t("doc_checks.setup.summary.#{action}", list: shown)]
    end
  end

  # The KYC field dropdown: standard fields first, then custom fields, by their on-screen label
  def doc_check_field_options(fields)
    fields.map { |f| [f.label, f.name, { data: { label: f.label } }] }
  end

  # [ok?, sentence] for one result row (resolutions first: they override the outcome)
  # Worked examples H3, H5, H6, E10, E11, E17, E18 — openspec/changes/document-checks/design.md#worked-examples
  def doc_check_result_sentence(result, record_label: "KYC")
    label = result.look_for
    vars = { label:, value: doc_check_display_value(result, result.doc_value),
             record: doc_check_display_value(result, result.record_value), record_label: }
    case result.resolution
    when "used_document_value"
      return [true, t("doc_checks.result.used_document_value", label:, user: result.resolved_by&.full_name)]
    when "marked_ok"
      return [true, t("doc_checks.result.marked_ok", user: result.resolved_by&.full_name, reason: result.resolve_reason)]
    end

    return [true, doc_check_ok_sentence(result, vars)] if result.outcome == "ok"

    [false, t("doc_checks.result.#{result.outcome}", **vars)]
  end

  def doc_check_ok_sentence(result, vars)
    case result.note
    when "filled" then t("doc_checks.result.filled", **vars)
    when "replaced" then t("doc_checks.result.replaced", **vars)
    when "kept"
      same = DocChecks::Judge.normalise(result.doc_value) == DocChecks::Judge.normalise(result.record_value)
      same ? t("doc_checks.result.kept_same", **vars) : t("doc_checks.result.kept", **vars)
    when "matches" then t("doc_checks.result.matches", **vars)
    else t("doc_checks.result.answer", **vars)
    end
  end

  # A settled item split for its aligned row on the tab: [status, detail, hint]. The detail is the value
  # shown (cut short on screen), the hint the other value, on hover. Worked examples H3, H5, H6, E10.
  def doc_check_ok_parts(result)
    status = ->(key) { t("doc_checks.panel.ok_status.#{key}") }
    user = result.resolved_by&.full_name
    # Values as the screen shows them (a date in the locale's format)
    doc_value = doc_check_display_value(result, result.doc_value)
    record_value = doc_check_display_value(result, result.record_value)
    # A person's resolution overrides the outcome
    case result.resolution
    when "used_document_value"
      return [status.call("used_document_value"), [doc_value, t("doc_checks.panel.ok_detail.by", user:)].compact_blank.join(" "), nil]
    when "marked_ok"
      return [status.call("marked_ok"), t("doc_checks.panel.ok_detail.marked_ok", user:, reason: result.resolve_reason), nil]
    end

    # What the check did on its own
    case result.note
    when "filled" then [status.call("filled"), doc_value, nil]
    when "replaced" then [status.call("replaced"), doc_value, t("doc_checks.panel.was", value: record_value)]
    when "kept"
      # Only worth a hint when the document said something different (compared as stored)
      same = DocChecks::Judge.normalise(result.doc_value) == DocChecks::Judge.normalise(result.record_value)
      [status.call("kept"), record_value, (t("doc_checks.panel.document_says", value: doc_value) unless same)]
    when "matches" then [status.call("matches"), doc_value, nil]
    else [status.call("answer"), doc_value, nil]
    end
  end

  # A stored value as the screen shows it: a date field's ISO value in the locale's date format
  # (CLAUDE.md: screens follow date.formats.default), anything else as stored.
  def doc_check_display_value(result, value)
    return value if value.blank? || result.field_name.blank? || !doc_check_date_field?(result)

    date = begin
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
    date ? l(date) : value
  end

  # Whether a result's field is a date field — the entity's fields are looked up once per request
  def doc_check_date_field?(result)
    @doc_check_date_fields ||= {}
    run = result.doc_check_run
    names = @doc_check_date_fields[[result.entity_id, run.record_type]] ||=
      DocChecks::Registry.for(run.record_type).fields_for(run.entity).select(&:date?).map(&:name)
    names.include?(result.field_name)
  end

  # What "Check documents" will do on this record, for the confirm modal (#confirmModal), in the shared
  # "Immediate Actions" layout (action_summary_modal.scss, as Request Updates): four short cards — what the AI
  # reads (and skips), what it fills in, where problems go, how long it takes.
  # The modal inserts the message with .html(), so everything is built escaped here.
  # Returns the data attributes for the button. Worked examples H3, H12, E10, E12 —
  # openspec/changes/document-checks/design.md#worked-examples
  def doc_check_run_confirm_data(record)
    # The KYC page asks twice (Actions menu and the tab): build it once per request
    @doc_check_run_confirm_data ||= {}
    @doc_check_run_confirm_data[[record.class.name, record.id]] ||= build_doc_check_run_confirm_data(record)
  end

  def build_doc_check_run_confirm_data(record)
    entry = DocChecks::Registry.for(record)
    checks = DocCheck.for_record(record).to_a
    scope = "doc_checks.run_confirm"
    # The documents with checks, split by whether this record has them uploaded
    present, missing = checks.map(&:document_name).uniq.partition { |name| entry.find_document(record, name) }
    reads_desc = [present.join(", "), (t("#{scope}.skipped", list: missing.join(", ")) if missing.any?)].compact_blank.join(". ")
    # Fill-in checks that overwrite a value already there turn the card amber
    replacing = checks.select { |c| present.include?(c.document_name) && c.action == "fill_in" && c.replace_existing }
                      .map(&:field_name).uniq.size

    cards = [
      [:blue, "ti-file-search", t("#{scope}.reads", count: present.size), reads_desc],
      if replacing.positive?
        [:amber, "ti-pencil", t("#{scope}.fills_replacing"), t("#{scope}.fills_replacing_desc", count: replacing)]
      else
        [:green, "ti-pencil", t("#{scope}.fills"), t("#{scope}.fills_desc")]
      end,
      [:amber, "ti-alert-triangle", t("#{scope}.decisions"), t("#{scope}.decisions_desc")],
      [:grey, "ti-clock", t("#{scope}.time"), t("#{scope}.time_desc")]
    ]
    { action: "click->confirm#popup", title: t("#{scope}.title"), msg: doc_check_action_summary(cards).to_str, method: "post" }
  end

  # The bulk Check documents confirm, in the same layout
  def doc_check_bulk_confirm_msg
    scope = "doc_checks.run_confirm"
    doc_check_action_summary([
                               [:blue, "ti-files", t("#{scope}.bulk.reads"), t("#{scope}.bulk.reads_desc")],
                               [:green, "ti-pencil", t("#{scope}.fills"), t("#{scope}.fills_desc")],
                               [:amber, "ti-alert-triangle", t("#{scope}.decisions"), t("#{scope}.bulk.decisions_desc")],
                               [:grey, "ti-clock", t("#{scope}.bulk.time"), t("#{scope}.bulk.time_desc")]
                             ]).to_str
  end

  # The "Use the document's value" confirm: what changes, that it is recorded, that Undo won't reverse it.
  # Worked example H5 — openspec/changes/document-checks/design.md#worked-examples
  def doc_check_use_value_confirm_msg(result, label)
    scope = "doc_checks.use_value_confirm"
    was = doc_check_display_value(result, result.record_value).presence || t("doc_checks.panel.empty_value")
    doc_check_action_summary([
                               [:blue, "ti-pencil", t("#{scope}.becomes", label:, value: doc_check_display_value(result, result.doc_value)), t("#{scope}.was", value: was)],
                               [:green, "ti-check", t("#{scope}.resolved"), t("#{scope}.resolved_desc")],
                               [:grey, "ti-arrow-back-up", t("#{scope}.no_undo"), t("#{scope}.no_undo_desc")]
                             ], intro_action: t("#{scope}.button")).to_str
  end

  # The "Immediate Actions" intro and one tinted card per [tint, icon, title, description]
  def doc_check_action_summary(cards, intro_action: t("common.proceed", default: "Proceed"))
    scope = "doc_checks.run_confirm"
    intro = tag.div(class: "action-summary__intro") do
      tag.div(t("#{scope}.intro_title"), class: "fw-bold text-dark") +
        tag.div(safe_join([t("#{scope}.intro_lead"), " ", tag.strong(intro_action), ":"]), class: "text-muted")
    end
    items = cards.map do |tint, icon, title, desc|
      tag.div(class: "action-summary__item action-summary__item--#{tint}") do
        tag.span(tag.i(class: "ti #{icon}"), class: "action-summary__icon") +
          tag.div(tag.div(title, class: "action-summary__title") + tag.div(desc, class: "action-summary__desc"))
      end
    end
    intro + tag.div(safe_join(items), class: "action-summary__list")
  end

  # The tab header line: progress, or when it was last checked and how many need attention
  def doc_check_header(assessment)
    run = assessment.active_run
    if run
      return t("doc_checks.panel.checking_start") if run.current_document.blank?

      return t("doc_checks.panel.checking", document: run.current_document, n: run.documents_done + 1, total: run.documents_total)
    end
    return t("doc_checks.panel.not_checked") unless assessment.checked?

    # The counts are on the summary bar; the header says when
    t("doc_checks.panel.checked_at", time: l(assessment.current_run.finished_at, format: :abbr_date_time))
  end
end
