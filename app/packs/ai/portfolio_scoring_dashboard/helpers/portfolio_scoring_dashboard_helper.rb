# frozen_string_literal: true

# View helpers for the Portfolio Scoring Dashboard.
#
# The dashboard carries several filters at once — tier/movement, count-vs-value
# basis, sector, tag and a name search. Every link on the page has to preserve
# the ones it is not changing, or clicking a tier card would silently drop the
# sector the FM had selected. This keeps that merge in one place instead of
# repeating a params hash in six partials.
module PortfolioScoringDashboardHelper
  # Builds a dashboard URL that keeps the current filters, applying only the
  # overrides given. Pass an explicit nil to clear one — e.g.
  # scoring_dashboard_path_with(status: nil) for a "Clear filter" link.
  #
  # @param overrides [Hash] params to change on top of the current ones
  # @return [String]
  def scoring_dashboard_path_with(overrides = {})
    portfolio_scoring_dashboard_path(**sticky_scoring_filters.merge(overrides).compact)
  end

  # The filters currently in force, in URL-param form.
  #
  # @return [Hash]
  def sticky_scoring_filters
    {
      status: @status_filter,
      basis: @basis == :value ? "value" : nil,
      sector: @sector_filter,
      tag: @tag_filter,
      # Only carried when they differ from the default, to keep shared URLs short.
      sort: @sort == PortfolioScoringDashboardController::DEFAULT_SORT ? nil : @sort,
      dir: @direction == PortfolioScoringDashboardController::DEFAULT_DIRECTION ? nil : @direction,
      q: @search_value.presence && { investor_investor_name_cont: @search_value }
    }
  end

  # URL for a sortable column header. Clicking the active column flips its
  # direction; clicking any other column starts it ascending.
  #
  # @param key [String] one of PortfolioScoringDashboardController::SORTABLE_COLUMNS
  # @return [String]
  def scoring_sort_path(key)
    flip = @sort == key && @direction == "asc" ? "desc" : "asc"
    scoring_dashboard_path_with(sort: key, dir: flip)
  end

  # Direction caret for the active sort column, blank for the others.
  #
  # @param key [String]
  # @return [String]
  def scoring_sort_caret(key)
    return "" unless @sort == key

    @direction == "asc" ? "▲" : "▼"
  end

  # Plain-language description of the current ordering, for the header tooltip.
  #
  # @param key [String]
  # @return [String]
  def scoring_sort_hint(key)
    return "Sort by #{key}" unless @sort == key

    @direction == "asc" ? "Sorted low to high — click to reverse" : "Sorted high to low — click to reverse"
  end

  # Whether the portfolio itself is narrowed — as opposed to just the table rows.
  # Sector and tag scope every number on the page, so the UI has to say so.
  #
  # @return [Boolean]
  def scoring_scope_narrowed?
    @sector_filter.present? || @tag_filter.present?
  end

  # Human description of the active portfolio scope, for the banner.
  #
  # @return [String]
  def scoring_scope_description
    [
      @sector_filter.presence && "sector #{@sector_filter}",
      @tag_filter.presence && "tag #{@tag_filter}"
    ].compact.join(" and ")
  end
end
