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

  # Display-only currency symbol for the report (e.g. "$", "₹") — no
  # conversion is applied, this only labels monetized columns. Returns nil
  # when no currency is configured (the default, matching today's behavior).
  def currency_symbol
    return nil if currency.blank?

    Money::Currency.new(currency).symbol
  rescue StandardError
    nil
  end

  # True when `clean_key` (a column key with any "; col-type" suffix already
  # stripped) resolves — on the root model, or on a model reached by walking
  # a dotted path of *real* AR associations from the root model (regardless
  # of whether that relation happens to be in config.joins; display-only, so
  # there's no injection surface to gate on join configuration here) — to a
  # Money attribute (a physical "<col>_cents" column with no plain "<col>" column).
  # Mirrors the identical monetized? helper duplicated in
  # ReportBuilderChildAggregator/ReportBuilderPivotAggregator, but exposed
  # here for the display layer (ReportBuilderTable, ReportBuilderXlsxExporter)
  # which has no other way to know a value came from a monetized attribute.
  def monetized?(clean_key)
    klass, bare_col = resolve_column(clean_key)
    return false unless klass

    klass.column_names.exclude?(bare_col) && klass.column_names.include?("#{bare_col}_cents")
  end

  private

  def strip_col_type(key)
    key.split(";").first.strip
  end

  def resolve_column(clean_key)
    parts = clean_key.to_s.split(".")
    bare_col = parts.pop
    klass = root_class

    parts.each do |part|
      reflection = klass.reflect_on_association(part.to_sym)
      return [nil, nil] unless reflection

      klass = reflection.klass
    end

    [klass, bare_col]
  rescue StandardError
    [nil, nil]
  end
end
