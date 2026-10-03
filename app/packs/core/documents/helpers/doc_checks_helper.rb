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

  def doc_check_action_options
    DocCheck::ACTIONS.map { |a| [t("doc_checks.setup.actions.#{a}"), a] }
  end

  # The KYC field dropdown: standard fields first, then custom fields, by their on-screen label
  def doc_check_field_options(fields)
    fields.map { |f| [f.label, f.name, { data: { label: f.label } }] }
  end

  # [ok?, sentence] for one result row (resolutions first: they override the outcome)
  # Worked examples H3, H5, H6, E10, E11, E17, E18 — openspec/changes/document-checks/design.md#worked-examples
  def doc_check_result_sentence(result, record_label: "KYC")
    label = result.look_for
    vars = { label:, value: result.doc_value, record: result.record_value, record_label: }
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

  # The tab header line: progress, or when it was last checked and how many need attention
  def doc_check_header(assessment)
    run = assessment.active_run
    if run
      return t("doc_checks.panel.checking_start") if run.current_document.blank?

      return t("doc_checks.panel.checking", document: run.current_document, n: run.documents_done + 1, total: run.documents_total)
    end
    return t("doc_checks.panel.not_checked") unless assessment.checked?

    time = l(assessment.current_run.finished_at, format: :abbr_date_time)
    count = assessment.attention_count
    count.zero? ? t("doc_checks.panel.checked.all_ok", time:) : t("doc_checks.panel.checked.attention", time:, count:)
  end
end
