# ④ Shape 2 — "every record has a required, signed document, signed on or before the record's date".
# The required document is a pack input (e.g. "ic_note") mapped per entity to a tag or name.
# Signed = CapHive e-sign completed (signed date = completion) or a wet-ink sign-off (entered date).
# Records before the check's "checks from" date are counted, not listed (H22, E25).
# Worked examples H22, H23, E25, E26, E27, E30, X26, E125, E127, E128 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceDocumentCheckQuery
  MAX_LISTED = 500

  Result = Struct.new(:checked, :ok, :failing, :earlier, :failing_count, keyword_init: true)
  DocRow = Struct.new(:id, :owner_id, :esign_status, :last_status_updated_at, keyword_init: true)

  def self.call(check, context)
    new(check, context).call
  end

  def initialize(check, context)
    @check = check
    @ctx = context
  end

  def call
    mapping = @ctx.setup&.document_mapping(@check["document_input"])
    raise ComplianceMeasureQuery::MissingInput, input_label if mapping.nil?

    records = record_scope.to_a
    from = Date.parse(@check["checks_from"].to_s)
    date_col = ComplianceDataCatalog.source(@check["source"]).record_date
    # Records before "checks from" are counted, not checked (E25)
    earlier, checked = records.partition { |r| r.public_send(date_col).nil? || r.public_send(date_col) < from }
    docs = documents_for(checked, mapping)
    signed_on = signed_dates(docs.values.flatten)

    failing = checked.filter_map { |rec| problem_for(rec, docs[rec.id] || [], signed_on, date_col) }
    Result.new(checked: checked.size, ok: checked.size - failing.size, failing: failing.first(MAX_LISTED),
               failing_count: failing.size, earlier: earlier.size)
  end

  private

  def input_label
    @ctx.input(@check["document_input"])["label"].presence || @check["document_input"].to_s.humanize
  end

  # Records of the fund matching the check's filters (e.g. buys only — E127); soft-deleted rows excluded (E125)
  def record_scope
    model = ComplianceDataCatalog.model(@check["source"])
    scope = model.where(entity_id: @ctx.fund.entity_id, fund_id: @ctx.fund.id)
    ComplianceMeasureQuery.new(@ctx).send(:apply_filters, scope, @check["source"], @check["filters"])
  end

  # Documents owned by the records, matched by the entity's tag or name mapping
  def documents_for(records, mapping)
    return {} if records.empty?

    model = ComplianceDataCatalog.model(@check["source"])
    scope = Document.where(entity_id: @ctx.fund.entity_id, owner_type: model.name, owner_id: records.map(&:id))
    scope = if mapping["tag"].present?
              scope.where("documents.tag_list LIKE ?", "%#{Document.sanitize_sql_like(mapping['tag'])}%")
            else
              scope.where(name: mapping["name"])
            end
    # Plain values, not Document instances — only these four columns are needed
    scope.pluck(:id, :owner_id, :esign_status, :last_status_updated_at)
         .map { |id, owner_id, status, at| DocRow.new(id:, owner_id:, esign_status: status, last_status_updated_at: at) }
         .group_by(&:owner_id)
  end

  # document id → signed date (wet ink entered date, else e-sign completion date)
  def signed_dates(docs)
    wet = DocumentSignoff.where(document_id: docs.map(&:id)).pluck(:document_id, :signed_on).to_h
    docs.each_with_object({}) do |d, h|
      date = wet[d.id] || (d.esign_status.to_s.casecmp?("completed") && d.last_status_updated_at&.to_date)
      h[d.id] = date if date
    end
  end

  def problem_for(rec, docs, signed_on, date_col)
    record_date = rec.public_send(date_col)
    base = { "id" => rec.id, "label" => record_label(rec), "date" => record_date&.iso8601 }
    return base.merge("problem" => "Missing", "code" => "missing") if docs.empty?

    # The earliest signed copy decides; re-uploading a later copy cannot clear "signed late" (E27)
    dates = docs.filter_map { |d| signed_on[d.id] }
    return base.merge("problem" => "Not signed — mark as signed (wet ink)", "code" => "not_signed") if dates.empty?

    first = dates.min
    # Timing uses the signed date, never the upload date (H23, E26); on by default
    return nil unless @check.fetch("on_or_before_record", true)
    return nil if record_date.nil? || first <= record_date

    base.merge("problem" => "Signed #{I18n.l(first)}, after investment date", "code" => "signed_late", "signed_on" => first.iso8601)
  end

  def record_label(rec)
    rec.respond_to?(:portfolio_company_name) && rec.portfolio_company_name.present? ? rec.portfolio_company_name : "##{rec.id}"
  end
end
