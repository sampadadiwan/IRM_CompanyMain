# Wraps the Report#template JSON into a typed value object.
class ReportBuilderConfig
  attr_reader :root_model, :joins, :aggregates, :root_filters, :sort, :currency, :formulas, :group_rows_by

  def initialize(template)
    t = (template || {}).with_indifferent_access

    @root_model    = t[:root_model].to_s
    @joins         = (t[:joins] || []).map(&:with_indifferent_access)
    @aggregates    = (t[:aggregates] || {}).with_indifferent_access
    @root_filters  = (t[:root_filters] || {}).with_indifferent_access
    @sort          = (t[:sort] || {}).with_indifferent_access
    @currency      = t[:currency]
    @formulas      = (t[:formulas] || []).map(&:with_indifferent_access)
    @group_rows_by = t[:group_rows_by]
  end

  def root_class
    root_model.constantize
  end

  def join_for(relation)
    joins.find { |j| j[:relation].to_s == relation.to_s }
  end

  # Returns the aggregate type for a given GridViewPreference key.
  # Tries both the raw key and the key without the "; col-type" suffix.
  def aggregate_for(gvp_key)
    aggregates[gvp_key] || aggregates[strip_col_type(gvp_key)]
  end

  def valid?
    root_model.present? && begin
      root_model.constantize
    rescue StandardError
      nil
    end.present?
  end

  private

  def strip_col_type(key)
    key.split(";").first.strip
  end
end
