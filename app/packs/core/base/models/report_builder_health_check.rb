# What will look wrong in a Report Builder report before anyone exports it:
# columns that will be blank, formulas using missing columns, money summed
# across currencies, filters matching nothing, oversized pivots, very large
# exports and columns on a default total. Each item names the tab that fixes it.
#
# Every check is bounded: one COUNT or DISTINCT over the entity's rows; the
# per-filter counts only run when the report has no rows at all.
#
# Worked examples H14, H15, E14–E18 — openspec/changes/report-builder-live-builder/business-rules.md
class ReportBuilderHealthCheck
  EXPORT_INFO_ROWS   = 50_000
  PIVOT_WARN_COLUMNS = 20

  # Overridable so a scenario can use a small export threshold (E18)
  class_attribute :export_info_rows, default: EXPORT_INFO_ROWS

  # user — whose rows the checks count: the person looking at the builder (M16)
  def initialize(report:, entity:, user:)
    @report = report
    @entity = entity
    @user   = user
    @config = ReportBuilderConfig.new(report.template)
  end

  # [{ level: :warning | :info, message:, tab: }], warnings first
  def items
    return [] unless @config.valid?

    @items ||= (blank_columns + broken_formulas + mixed_currencies + empty_filters + large_pivots +
                large_export + default_totals).sort_by { |i| i[:level] == :warning ? 0 : 1 }
  rescue ActiveRecord::StatementInvalid, ArgumentError, NameError => e
    # A check that can't run never blocks the builder; the preview shows the real error
    Rails.logger.warn "[ReportBuilderHealthCheck] #{e.message}"
    []
  end

  def warnings_count
    items.count { |i| i[:level] == :warning }
  end

  private

  def engine
    @engine ||= ReportBuilderQueryEngine.new(report: @report, entity: @entity, user: @user)
  end

  def row_count
    @row_count ||= engine.count
  end

  def column_type
    @config.column_type
  end

  # The report's real columns: no formula / pivot position rows
  def gvps
    @gvps ||= @report.grid_view_preferences.reorder(:sequence, :id).to_a
                     .reject { |g| g.key.start_with?("formula:", "pivot:") }
  end

  def clean(gvp)
    gvp.key.split(";").first.to_s.strip
  end

  def label(gvp)
    gvp.label.presence || gvp.name
  end

  def warning(message, tab)
    { level: :warning, message: message, tab: tab }
  end

  def info(message, tab)
    { level: :info, message: message, tab: tab }
  end

  # E14 — related data that no longer resolves, or a field that isn't on it
  def blank_columns
    gvps.filter_map do |gvp|
      key = clean(gvp)
      next unless key.include?(".")

      relation = column_type.relation_for(key)
      next warning("#{label(gvp)} will be blank — its related data no longer exists", "related") unless column_type.strategy_for(relation)

      klass = ReportBuilderColumnCatalog.related_class(@config.root_class, relation)
      field = key.delete_prefix("#{relation}.")
      next if field.include?(".") || ReportBuilderColumnCatalog.related_columns_for(klass).any? { |c| c[:key] == field }

      warning("#{label(gvp)} will be blank — #{field} isn't a field of #{relation.humanize.downcase}", "columns")
    end
  end

  # E15 — a formula using a column that isn't in the report
  def broken_formulas
    known = gvps.map { |g| clean(g) } + (@config.formulas || []).map { |f| f["key"].to_s }
    (@config.formulas || []).flat_map do |formula|
      refs = formula["expression"].to_s.scan(/\[([^\]]+)\]/).flatten.map { |r| r.split(";").first.strip }
      (refs.uniq - known).map do |missing|
        warning("Formula #{formula['label']} uses #{missing}, which isn't in the report", "formulas")
      end
    end
  end

  # H15 — money summed over funds of different currencies
  def mixed_currencies
    return fund_rows_currencies if @config.root_class == Fund

    gvps.filter_map do |gvp|
      key = clean(gvp)
      next unless column_type.type_for(key) == :money

      currencies = currencies_behind(key)
      next unless currencies && currencies.size > 1

      warning("#{label(gvp)} adds amounts in #{currencies.sort.to_sentence} — pick a fund or split by fund", "filters")
    end
  end

  # Each row is one fund, so a row never mixes currencies — only the totals
  # row adds funds together. A note, not a warning ("pick a fund" would be
  # wrong advice). Worked example E9 — report-builder-starting-points.
  def fund_rows_currencies
    return [] unless gvps.any? { |gvp| column_type.type_for(clean(gvp)) == :money && column_type.totalable?(clean(gvp)) }

    currencies = Fund.where(id: engine.rows_scope.unscope(:order).select(:id)).distinct.pluck(:currency).compact
    return [] unless currencies.size > 1

    [info("The totals row adds funds in #{currencies.sort.to_sentence}", "sort")]
  end

  # The currencies of the funds behind a summed money column, or nil when it
  # isn't summed or its rows have no fund
  def currencies_behind(key)
    if key.include?(".")
      relation = column_type.relation_for(key)
      return nil unless column_type.strategy_for(relation) == :grouped && @config.effective_aggregate(key) == "sum"

      scope = engine.related_scope(relation)
    else
      # A root money column is summed in the totals row
      scope = engine.rows_scope
    end
    return nil unless scope.klass.column_names.include?("fund_id")

    Fund.where(id: scope.unscope(:order).select(:fund_id)).distinct.pluck(:currency).compact
  end

  # E16 — when nothing comes back, the filters that alone match nothing
  def empty_filters
    return [] if row_count.positive?

    @config.root_filters.filter_map do |pred_key, value|
      alone = Report.new(template: @report.template.merge("root_filters" => { pred_key => value }))
      matching = ReportBuilderQueryEngine.new(report: alone, entity: @entity, user: @user).count # an Integer of rows
      next if matching.positive?

      warning("No rows match #{filter_words(pred_key, value)}", "filters")
    end
  end

  # "Category is Partner"
  def filter_words(pred_key, value)
    ReportBuilderFilterField.describe(config: @config, entity: @entity, pred_key: pred_key, value: value)
  end

  # E17 — a pivot that would spread over too many columns
  def large_pivots
    @config.joins.filter_map do |join|
      pivot = (join[:pivot] || {}).with_indifferent_access
      group_bys = Array(pivot[:group_bys] || pivot[:group_by]).compact_blank
      next if group_bys.empty? || pivot[:value_col].blank?

      count = engine.pivot_preview(join[:relation].to_s, group_bys, pivot[:value_col])[:count].to_i
      next if count <= PIVOT_WARN_COLUMNS

      warning("#{join[:relation].to_s.humanize} pivot creates #{count} columns — consider fewer categories", "related")
    end
  end

  # E18 — very large exports take a while
  def large_export
    return [] unless row_count > export_info_rows

    [info("Export will have #{row_count} rows — it may take a while", "delivery")]
  end

  # E18 — many-per-row related columns saved without a total use the default
  def default_totals
    gvps.filter_map do |gvp|
      key = clean(gvp)
      next unless key.include?(".") && @config.aggregate_for(gvp.key).nil?

      default = column_type.default_aggregate(key)
      next unless default

      info("#{label(gvp)} uses the default total #{ReportBuilderColumnType.aggregate_label(default)}", "columns")
    end
  end
end
