# frozen_string_literal: true

# View helpers for the Presentation Analyst Dashboard. Mirrors
# PortfolioScoringDashboardHelper's sticky-filter pattern — every link on the
# page has to preserve the filters it is not changing, or clicking a tier
# card would silently drop the sector/tag scope the FM had selected.
module PresentationAnalystDashboardHelper
  # @param overrides [Hash] params to change on top of the current ones
  # @return [String]
  def presentation_dashboard_path_with(overrides = {})
    presentation_analyst_dashboard_path(**sticky_presentation_filters.merge(overrides).compact)
  end

  # @return [Hash]
  def sticky_presentation_filters
    {
      status: @status_filter,
      sector: @sector_filter,
      tag: @tag_filter,
      sort: @sort == PresentationAnalystDashboardController::DEFAULT_SORT ? nil : @sort,
      dir: @direction == PresentationAnalystDashboardController::DEFAULT_DIRECTION ? nil : @direction,
      q: @search_value.presence && { investor_investor_name_cont: @search_value }
    }
  end

  # @param key [String] one of PresentationAnalystDashboardController::SORTABLE_COLUMNS
  # @return [String]
  def presentation_sort_path(key)
    flip = @sort == key && @direction == "asc" ? "desc" : "asc"
    presentation_dashboard_path_with(sort: key, dir: flip)
  end

  # @param key [String]
  # @return [String]
  def presentation_sort_caret(key)
    return "" unless @sort == key

    @direction == "asc" ? "▲" : "▼"
  end

  # @param key [String]
  # @return [String]
  def presentation_sort_hint(key)
    return "Sort by #{key}" unless @sort == key

    @direction == "asc" ? "Sorted low to high — click to reverse" : "Sorted high to low — click to reverse"
  end

  # @return [Boolean]
  def presentation_scope_narrowed?
    @sector_filter.present? || @tag_filter.present?
  end

  # @return [String]
  def presentation_scope_description
    [
      @sector_filter.presence && "sector #{@sector_filter}",
      @tag_filter.presence && "tag #{@tag_filter}"
    ].compact.join(" and ")
  end
end
