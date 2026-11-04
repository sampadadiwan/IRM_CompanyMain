# A reader's own filters on the report page ("Narrow down"): the `q` params of
# this visit, kept only when they are on one of the report's root filter fields
# with a known operator, and never on a field the report itself already filters
# on — the report's "shows only LPs" must stay true. Nothing here is saved, and
# the export stays the whole report.
#
#   report filters category_eq: LP;  q = { city_eq: Mumbai, category_eq: Co-Investor, no_such_eq: x }
#     applied → { "city_eq" => "Mumbai" }                       (to the engine as external_filters)
#     chips   → [{ key: "city_eq", text: "City is Mumbai" }]
#     dropped → ["Category is already set by the report"]       (no_such_eq is ignored silently)
#
# Worked examples H10, E8, E9, E10 — openspec/changes/report-builder-delivery/business-rules.md
class ReportBuilderReaderFilters
  def initialize(config:, entity:, q:)
    @config = config
    @entity = entity
    @q      = q.respond_to?(:to_unsafe_h) ? q.to_unsafe_h : (q || {}).to_h
  end

  # { pred_key => value } for the engine
  def applied
    @applied ||= candidates.reject { |pred_key, _| saved_fields.include?(field_of(pred_key)) }
  end

  # [{ key:, text: }] — one removable chip per applied filter
  def chips
    applied.map do |pred_key, value|
      { key: pred_key,
        text: ReportBuilderFilterField.describe(config: @config, entity: @entity, pred_key: pred_key, value: value) }
    end
  end

  # Why a reader filter was left out (E9)
  def dropped
    candidates.keys.select { |pred_key| saved_fields.include?(field_of(pred_key)) }.map do |pred_key|
      "#{ReportBuilderColumnCatalog.label_for(@config, field_of(pred_key))} is already set by the report"
    end.uniq
  end

  private

  # Known operator, a root filter field, and a value unless the operator needs none (E10)
  def candidates
    @candidates ||= @q.each_with_object({}) do |(pred_key, value), kept|
      field, op = ReportBuilderFilterField.split_predicate(pred_key)
      next unless op && allowed_fields.include?(field)

      value = value.to_s.split(",").map(&:strip).compact_blank if op.end_with?("in") && value.is_a?(String)
      next if Array(value).compact_blank.empty? && ReportBuilderFilterField::NO_VALUE_OPS.exclude?(op)

      kept[pred_key.to_s] = value
    end
  end

  def field_of(pred_key)
    ReportBuilderFilterField.split_predicate(pred_key).first
  end

  def allowed_fields
    @allowed_fields ||= ReportBuilderColumnCatalog.filter_columns_for(@config.root_class).to_set { |c| c[:key] }
  end

  # The fields the report's own (root) filters use
  def saved_fields
    @saved_fields ||= @config.root_filters.keys.to_set { |pred_key| field_of(pred_key) }
  end
end
