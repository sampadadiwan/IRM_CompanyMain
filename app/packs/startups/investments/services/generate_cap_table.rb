class GenerateCapTable < Trailblazer::Operation
  step :initialize_params
  step :fetch_investments
  step :calculate_holdings
  step :merge_shareholder_positions
  step :calculate_totals
  step :format_result

  def initialize_params(options, params:, **)
    options[:funding_rounds] = params[:funding_rounds]
    options[:portfolio_company_id] = params[:portfolio_company_id]
    options[:group_by_field] = params[:group_by_field] || :investor_name
  end

  def fetch_investments(options, funding_rounds:, portfolio_company_id:, **)
    options[:investments] = Investment.where(
      funding_round: funding_rounds,
      portfolio_company_id: portfolio_company_id
    ).includes(portfolio_company: :entity)
    options[:portfolio_company] = Investor.find_by(id: portfolio_company_id)
  end

  def calculate_holdings(options, investments:, group_by_field:, **)
    # Separate equity and convertible investments
    equity_investments = investments.where(investment_type: "Equity")
    convertible_investments = investments.where(investment_type: "Convertible")

    # Compute current holdings (excluding convertibles)
    options[:current_holdings] = equity_investments.group(group_by_field).sum(:quantity)

    # Compute total convertibles for each investor
    options[:convertibles] = convertible_investments.group(group_by_field).sum(:quantity)

    # Track each group's distinct Investment#instrument_name value(s), so format_result can
    # expose an "Instrument" column here too - mirrored by merge_shareholder_positions below,
    # which folds in ShareholderPosition#instrument the same way.
    instruments_by_group = Hash.new { |h, k| h[k] = Set.new }
    investments.each do |investment|
      grouping_value = investment.send(group_by_field)
      next if grouping_value.blank? || investment.instrument_name.blank?

      instruments_by_group[grouping_value] << investment.instrument_name.strip
    end
    options[:instruments_by_group] = instruments_by_group
  end

  # Folds in ShareholderPosition amounts (e.g. Founders/Employees/Stakeholders uploaded via
  # "Upload Stakeholder Positions") whose round matches one of the requested funding_rounds -
  # either via an explicit round_name (e.g. "Seeding") or a position_date falling in a round
  # named after that month/year. When the row has no real "Quantity Actuals" count, the whole
  # uploaded Fully Diluted Quantity goes into the convertible/dilution bucket (the pre-existing
  # behavior for a percent-only or quantity-only upload); when it does, the real count goes into
  # the equity bucket and only the remainder goes into the dilution bucket.
  def merge_shareholder_positions(options, portfolio_company_id:, funding_rounds:, group_by_field:, convertibles:, current_holdings:, instruments_by_group:, **)
    rounds = Array(funding_rounds)
    options[:percentage_overrides] = {}
    return true if rounds.blank?

    positions = ShareholderPosition
                .approved
                .where(portfolio_company_id: portfolio_company_id)
                .where.not(position_amount: nil)
                .includes(:investor)
                .select { |sp| self.class.shareholder_position_matches_round?(sp, rounds) }

    return true if positions.blank?

    # Multiple ShareholderPosition rows for the same group can appear here across the cumulative
    # funding_rounds window (e.g. one snapshot uploaded per round) - each is a full restatement
    # of that group's position as of its round, not an incremental delta, so only the latest
    # row's typed % (by upload order) is used as the override. Summing every matching row's %
    # together would double-count across rounds (e.g. 50% + 48% = 98%), the same way summing raw
    # quantities would if they weren't genuinely additive.
    latest_position_by_group = {}

    positions.sort_by { |sp| [sp.created_at, sp.id] }.each do |sp|
      grouping_value = group_by_field.to_sym == :category ? sp.category : (sp.investor_label.presence || sp.investor&.investor_name)
      next if grouping_value.blank?

      latest_position_by_group[grouping_value] = sp
    end

    # Only fold in each group's latest restatement (the same row already selected above for
    # percentage_overrides) - iterating every matching row here would double-count a group that
    # has a snapshot in more than one round within the cumulative funding_rounds window, the same
    # way summing every row's % would.
    latest_position_by_group.each_value do |sp|
      grouping_value = group_by_field.to_sym == :category ? sp.category : (sp.investor_label.presence || sp.investor&.investor_name)
      next if grouping_value.blank?

      fully_diluted_amount = sp.position_amount.to_f
      quantity_actual_amount = sp.quantity_actual.presence&.to_f || 0.0

      # An optional "Quantity Actuals" upload column is a real (non fully-diluted) share/unit
      # count for the row - fold it into the same equity bucket Investment-driven quantities
      # use, so the "Quantity" column reflects it instead of always showing 0 for portfolio
      # companies whose cap table comes entirely from ShareholderPosition uploads. Only the
      # remaining portion of the uploaded Fully Diluted Quantity (beyond that real count) goes
      # into the convertible/dilution bucket, so the two buckets still sum back to the
      # uploaded Fully Diluted Quantity total instead of double-counting it.
      current_holdings[grouping_value] = current_holdings[grouping_value].to_f + quantity_actual_amount if quantity_actual_amount.positive?
      convertibles[grouping_value] = convertibles[grouping_value].to_f + (fully_diluted_amount - quantity_actual_amount)
      instruments_by_group[grouping_value] << sp.instrument.strip if sp.instrument.present?
    end

    options[:percentage_overrides] = latest_position_by_group.filter_map do |grouping_value, sp|
      [grouping_value, sp.fully_diluted_percentage.to_f] if sp.fully_diluted_percentage.present?
    end.to_h

    true
  end

  def calculate_totals(options, current_holdings:, convertibles:, **)
    # Merge both hashes to get all unique investors
    options[:all_investors] = (current_holdings.keys + convertibles.keys).uniq

    # Compute total outstanding shares for percentage calculations
    total_equity = current_holdings.values.sum
    total_fully_diluted = total_equity + convertibles.values.sum

    # Handle case where only convertibles exist
    total_equity = total_fully_diluted if total_equity.zero?

    options[:total_equity] = total_equity
    options[:total_fully_diluted] = total_fully_diluted
  end

  def format_result(options, all_investors:, investments:, group_by_field:, current_holdings:, convertibles:, total_equity:, total_fully_diluted:, portfolio_company:, percentage_overrides: {}, instruments_by_group: {}, **)
    return options[:model] = [] if total_fully_diluted.zero?

    # Generate the cap table
    cap_table = all_investors.map do |grouping_field|
      # Find one investment to get the category
      investment = investments.find { |i| i.send(group_by_field) == grouping_field }

      # When grouping by :category, grouping_field IS the category itself (e.g. "Self"), so we
      # can determine is_self directly - this also covers companies whose "Self" holdings come
      # only from ShareholderPosition uploads and have no matching Investment record at all.
      is_self = group_by_field.to_sym == :category ? grouping_field == "Self" : investment&.category == "Self"
      display_name = is_self ? (portfolio_company&.entity&.name || grouping_field) : grouping_field

      equity_quantity = current_holdings[grouping_field] || 0
      convertible_quantity = convertibles[grouping_field] || 0
      diluted_quantity = equity_quantity + convertible_quantity

      percentage = total_equity.positive? ? (equity_quantity.to_f / total_equity * 100).round(2) : 0.0

      # A persisted Fully Diluted % (typed in at upload time on the underlying
      # ShareholderPosition rows) is trusted over the quantity-derived ratio, consistent with
      # GenerateHorizontalCapTable - only fall back to computing from quantities when this
      # group has no persisted % at all.
      fully_diluted_percentage_value = percentage_overrides[grouping_field] || (diluted_quantity.to_f / total_fully_diluted * 100)

      # A group can hold more than one distinct instrument (e.g. an Equity stake and a separate
      # CCPS stake blended into this same investor row, since this table doesn't split rows per
      # instrument the way GenerateHorizontalCapTable does) - show them all rather than silently
      # picking one and hiding the rest. "-" when the group has none at all.
      group_instruments = instruments_by_group[grouping_field]
      instrument = group_instruments.present? ? group_instruments.to_a.sort.join(", ") : "-"

      {
        grouping_field: display_name,
        is_self: is_self,
        instrument: instrument,
        quantity: equity_quantity.to_f.round(2),
        percentage: "#{percentage}%",
        fully_diluted: diluted_quantity.to_f.round(2),
        fully_diluted_percentage: "#{fully_diluted_percentage_value.round(2)}%",
        # Full, unrounded percentage - used by callers (e.g. the Ownership Trend chart) that
        # need more precision than the 2dp display string above.
        fully_diluted_percentage_value: fully_diluted_percentage_value
      }
    end

    # Append total row
    cap_table << {
      grouping_field: "Total",
      instrument: "-",
      quantity: total_equity.to_f.round(2),
      percentage: "100.0%",
      fully_diluted: total_fully_diluted.to_f.round(2),
      fully_diluted_percentage: "100.0%",
      fully_diluted_percentage_value: 100.0
    }

    options[:model] = cap_table
  end

  # A ShareholderPosition's round matches one of the requested funding rounds either via an
  # explicit round_name (e.g. "Seeding") or, when only a position_date was provided, via that
  # date's "Month Year" label (e.g. a March 2025 position matching a "March 2025" round). Public
  # (and a class method, not an instance step) so views can reuse the exact same matching rule to
  # find pending Fully Diluted updates staged against a given round (see _funding_round.html.erb).
  def self.shareholder_position_matches_round?(shareholder_position, rounds)
    return true if shareholder_position.round_name.present? && rounds.include?(shareholder_position.round_name)
    return false if shareholder_position.position_date.blank?

    rounds.include?(shareholder_position.position_date.strftime("%B %Y"))
  end
end
