# Service for preparing data for KPI Budget View.
#
# This service encapsulates the logic for retrieving and filtering Investor KPI mappings
# and organizing KPI reports into quarterly and yearly groups for display in budget views.
class KpiBudgetViewService
  Result = Struct.new(:investor_kpi_mappings, :quarterly_reports, :year_reports, :grouped_quarterly_reports, :grouped_yearly_reports, :show_achievement_column, :tag_lists_to_display, :precision, keyword_init: true)

  def self.call(current_user, params, kpi_reports, tag_list)
    new(current_user, params, kpi_reports, tag_list).call
  end

  def initialize(current_user, params, kpi_reports, tag_list)
    @current_user = current_user
    @params = params
    @kpi_reports = kpi_reports
    @tag_list = tag_list
  end

  def call
    quarterly_reports = filter_reports('Quarter')
    year_reports = filter_reports('Year')

    Result.new(
      investor_kpi_mappings: fetch_investor_kpi_mappings,
      quarterly_reports: quarterly_reports,
      year_reports: year_reports,
      grouped_quarterly_reports: group_reports(quarterly_reports, @tag_list),
      grouped_yearly_reports: group_reports(year_reports, @tag_list),
      show_achievement_column: show_achievement_column?,
      tag_lists_to_display: @tag_list,
      precision: @params[:decimals]&.to_i || 2
    )
  end

  private

  def show_achievement_column?
    @tag_list.include?('Actual') && @tag_list.include?('Budget')
  end

  def primary_tag_for_filtering
    @primary_tag_for_filtering ||= @tag_list.find { |tag| tag != 'Actual' } || 'Actual'
  end

  def num_periods_to_display
    @num_periods_to_display ||= @params[:num_periods]&.to_i || 1
  end

  def filter_reports(period)
    base_reports = @kpi_reports.filter { |r| r.period == period && r.tag_list == primary_tag_for_filtering }
                               .sort_by(&:as_of)
                               .last(num_periods_to_display)

    as_of_dates = base_reports.map(&:as_of).uniq

    @kpi_reports.filter { |r| r.period == period && r.as_of.present? && as_of_dates.include?(r.as_of) }
  end

  def fetch_investor_kpi_mappings
    investor = Investor.where(id: @params[:portfolio_company_id]).first

    if ["Investment Fund", "Angel Fund"].include? @current_user.entity.entity_type
      # Create dummy mappings for the startup, which has all the kpi names
      investor_kpi_mappings = investor.investor_kpi_mappings
      investor_kpi_mappings = investor_kpi_mappings.where(category: @params[:categories].split(",")) if @params[:categories].present?
    else
      # Using standard_kpi_name twice as per original code logic (though likely typo there, safe to preserve)
      investor_kpi_mappings = Kpi.where(kpi_report_id: @kpi_reports.pluck(:id)).pluck(:name).uniq.map { |kpi_name| InvestorKpiMapping.new(standard_kpi_name: kpi_name, category: "General") }
    end

    # Filter investor_kpi_mappings based on the category if provided
    if @params[:category].present?
      # If it's an array (from dummy mapping above), use select. If it's Relation, use select too (or where if Relation)
      # Original code used .select on both which implies it works on Array or Relation loaded to array.
      # But `investor.investor_kpi_mappings` returns Relation. `.select` on relation triggers query or filtering in ruby.
      # Given existing code used `.select`, I will use it.
      investor_kpi_mappings = investor_kpi_mappings.select { |ikm| ikm.category == @params[:category] }
    end

    investor_kpi_mappings
  end

  def group_reports(reports, tags)
    reports.group_by(&:as_of).transform_values do |reports_for_date|
      tags.index_with do |tag|
        reports_for_date.find { |r| r.tag_list == tag }
      end
    end
  end
end
