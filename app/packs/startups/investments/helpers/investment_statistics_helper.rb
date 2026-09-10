module InvestmentStatisticsHelper
  # 1. Column Chart for Amount by Funding Round
  def investment_amount_by_funding_round(investments, shareholder_positions: ShareholderPosition.none, category: nil)
    investments = investments.where(category: category) if category.present?
    shareholder_positions = shareholder_positions.where(category: category) if category.present?

    # Get the earliest investment date for each funding round
    funding_round_dates = investments.reorder(nil)
                                     .group(:funding_round)
                                     .minimum(:investment_date) # Get earliest investment date per round

    # Compute the total amount per funding round
    funding_round_amounts = investments.reorder(nil)
                                       .group(:funding_round)
                                       .sum("amount_cents/100")

    # Fold in any uploaded ShareholderPosition amounts booked against a round (e.g. "Seeding")
    # that may have no matching Investment record at all.
    shareholder_position_amounts_by_round(shareholder_positions).each do |round, amount|
      funding_round_amounts[round] = funding_round_amounts[round].to_f + amount
      funding_round_dates[round] = nil unless funding_round_dates.key?(round)
    end

    # Sort funding rounds by their earliest investment date; rounds with no investment date
    # (introduced only via a ShareholderPosition) are ordered after the dated ones.
    ordered_funding_rounds = funding_round_dates.sort_by { |_round, date| [date.nil? ? 1 : 0, date || 0] }.map(&:first)

    # Ensure the funding round amounts are displayed in chronological order
    sorted_data = ordered_funding_rounds.map { |round| [round, funding_round_amounts[round] || 0] }

    column_chart sorted_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  # 4. Line Chart for Self Ownership Trend over Time (%stake fully diluted)
  def self_ownership_trend(investments, shareholder_positions: ShareholderPosition.none, portfolio_company_id: nil)
    portfolio_company_id ||= investments.first&.portfolio_company_id
    return if portfolio_company_id.blank?

    portfolio_company = Investor.find_by(id: portfolio_company_id)
    return if portfolio_company.blank?

    ordered_rounds = ordered_funding_rounds(investments, shareholder_positions)
    return if ordered_rounds.empty?

    cumulative_rounds = []

    sorted_self_data = ordered_rounds.map do |round|
      cumulative_rounds << round

      # Use generate_cap_table logic to get correct fully diluted percentage
      result = GenerateCapTable.call(params: {
                                       funding_rounds: cumulative_rounds,
                                       portfolio_company_id: portfolio_company.id,
                                       group_by_field: :category
                                     })
      cap_table = result[:model]

      # Find the "Self" category row in the generated cap table
      self_row = cap_table.find { |row| row[:grouping_field] == portfolio_company.entity.name }

      # Use the precise (unrounded) percentage value from GenerateCapTable#format_result -
      # rather than self_row[:fully_diluted_percentage], which is a string already rounded to
      # 1dp for the Cap Table tables. This already honors a persisted Fully Dilluted % typed in
      # at upload time (preferred over the quantity-derived ratio) the same way the Cap Table
      # tables do, so the chart and tables always agree.
      percentage = if self_row
                     (self_row[:fully_diluted_percentage_value] || 0.0).round(2)
                   else
                     0.0
                   end
      [round, percentage]
    end

    # discrete: true forces Chartkick to treat the round labels (e.g. "March 2025") as plain
    # category strings instead of auto-detecting them as dates. Without this, Chartkick/Highcharts
    # parses a month/year-only label like "March 2025" as a JS Date, which defaults the missing
    # day-of-month to the 1st - so an upload dated 31/03/2025 would incorrectly display as
    # "Mar 1, 2025" on the chart even though the underlying data is correct.
    line_chart sorted_self_data, discrete: true, library: {
      yAxis: {
        title: { text: "Percentage (%)" },
        labels: { format: "{value}%" }
      },
      plotOptions: {
        line: {
          dataLabels: {
            enabled: true,
            format: "{point.y:.2f}%"
          }
        }
      },
      **chart_theme_color
    }
  end

  # 2. Pie Chart for Fully Diluted Holding Across Investors
  # chart_type: :pie, :donut (default), or :half_donut
  def fully_diluted_holdings(investments, shareholder_positions: ShareholderPosition.none, portfolio_company_id: nil, chart_type: :donut)
    portfolio_company_id ||= investments.first&.portfolio_company_id || shareholder_positions.first&.portfolio_company_id

    # Each ShareholderPosition snapshot (e.g. one uploaded "As Of" March 2025, another September
    # 2025) is a full restatement of every investor's position as of that round, not an
    # incremental delta - naively summing shareholder_positions.position_amount across every
    # round here would double/triple-count investors who have a row in more than one round,
    # while investors who only ever appear in a single round would be comparatively
    # under-counted (diluting their slice unfairly). GenerateCapTable already gets this right
    # (same restatement-aware dedup used by the Cap Table by Funding Round tables and the
    # Ownership Trend chart), so reuse it here too instead of re-deriving holdings by hand -
    # this also means a persisted Fully Dilluted % typed in at upload time is honored the same
    # way it is everywhere else.
    fully_diluted = if portfolio_company_id.present?
                      ordered_rounds = ordered_funding_rounds(investments, shareholder_positions)

                      if ordered_rounds.present?
                        result = GenerateCapTable.call(params: {
                                                         funding_rounds: ordered_rounds,
                                                         portfolio_company_id: portfolio_company_id
                                                       })
                        result[:model].reject { |row| row[:grouping_field] == "Total" }
                                      .map { |row| [row[:grouping_field], row[:fully_diluted]] }
                      else
                        []
                      end
                    else
                      []
                    end

    # Override just the slice data label precision to 2dp for this chart - pie_chart_with_options'
    # own default (1dp) is shared with unrelated Fund/Portfolio pie charts, which stay unchanged.
    pie_chart_with_options fully_diluted, chart_type:, library: {
      plotOptions: {
        pie: {
          dataLabels: {
            format: '{point.name}:<br>{point.percentage:.2f} %'
          }
        }
      }
    }
  end

  # 3. Column Chart for Amount Per Investor
  def investment_amount_by_investor(investments, shareholder_positions: ShareholderPosition.none)
    grouped_data = investments.reorder(nil).group(:investor_name)
                              .sum("amount_cents/100") # Compute total amount

    # Fold in any uploaded ShareholderPosition amounts for investors
    shareholder_position_amounts_by_investor(shareholder_positions).each do |investor_name, amount|
      grouped_data[investor_name] = grouped_data[investor_name].to_f + amount
    end

    # Sort the data alphabetically by investor name
    sorted_data = grouped_data.sort_by { |investor_name, _amount| investor_name }

    column_chart sorted_data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "{point.y:,.2f}"
          }
        }
      },
      **chart_theme_color
    }
  end

  private

  # Funding rounds in chronological order, from Investment records...
  #
  # ...folding in any rounds that only exist via uploaded ShareholderPosition records (e.g. a
  # "Self" position with no matching Investment record at all), so companies whose ownership
  # is tracked solely through stakeholder uploads still get every round. These are appended
  # in upload order (oldest snapshot first) rather than by date, since a label like "Founding"
  # intentionally has no calendar date but still represents the earliest point in the
  # company's history - mirroring the ordering used by GenerateHorizontalCapTable.
  def ordered_funding_rounds(investments, shareholder_positions)
    ordered_rounds = investments.reorder(nil).group(:funding_round).minimum(:investment_date)
                                 .sort_by { |_round, date| date }.map(&:first)

    shareholder_positions.where.not(position_amount: nil).order(:created_at, :id).each do |position|
      round_label = position.round_name.presence || position.position_date&.strftime("%B %Y")
      next if round_label.blank?

      ordered_rounds << round_label unless ordered_rounds.include?(round_label)
    end

    ordered_rounds
  end

  # Groups ShareholderPosition#position_amount by funding round label, preferring the row's
  # round_name (e.g. a stakeholder-only round like "Seeding") and falling back to the
  # position_date formatted as "Month Year" when no round_name was provided.
  def shareholder_position_amounts_by_round(shareholder_positions)
    shareholder_positions.where.not(position_amount: nil).each_with_object(Hash.new(0)) do |position, totals|
      round_label = position.round_name.presence || position.position_date&.strftime("%B %Y")
      next if round_label.blank?

      totals[round_label] += position.position_amount.to_f
    end
  end

  # Groups ShareholderPosition#position_amount by investor, preferring the row's
  # investor_label (as set at import time) and falling back to the linked Investor's name -
  # mirroring the resolution used in GenerateHorizontalCapTable#merge_shareholder_positions.
  def shareholder_position_amounts_by_investor(shareholder_positions)
    shareholder_positions.where.not(position_amount: nil).includes(:investor).each_with_object(Hash.new(0)) do |position, totals|
      investor_name = position.investor_label.presence || position.investor&.investor_name
      next if investor_name.blank?

      totals[investor_name] += position.position_amount.to_f
    end
  end
end
