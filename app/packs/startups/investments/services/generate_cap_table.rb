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
    # group_by_field may also be an Array of fields (e.g. [:investor_name, :category]) to keep
    # the same investor in separate rows per category - each grouping value is then an Array.
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
    # Grouped in Ruby rather than with SQL GROUP BY so group_by_field can include the derived
    # :instrument key (see investment_grouping_value), which has no single backing column.
    #
    # A Convertible's Quantity is its fully diluted (as-converted) quantity, while its Instrument
    # Quantity is the actual number of instruments held (e.g. 15 CCPS converting into 1500 shares).
    # So "Quantity actual" is Equity quantity plus Convertible instrument_quantity, and only the
    # remainder of the Convertible's Quantity goes into the dilution bucket - mirroring how
    # merge_shareholder_positions splits Quantity Actuals from the Fully Diluted Quantity below,
    # so actual + convertibles still sums back to the Quantity column.
    current_holdings = {}
    convertibles = {}

    # Track each group's distinct Instrument value(s), so format_result can expose an
    # "Instrument" column here too - mirrored by merge_shareholder_positions below, which folds
    # in ShareholderPosition#instrument the same way.
    instruments_by_group = Hash.new { |h, k| h[k] = Set.new }

    investments.each do |investment|
      grouping_value = self.class.investment_grouping_value(investment, group_by_field)

      case investment.investment_type
      when "Equity"
        current_holdings[grouping_value] = current_holdings[grouping_value].to_f + investment.quantity.to_f
      when "Convertible"
        instrument_quantity = investment.instrument_quantity.to_f
        current_holdings[grouping_value] = current_holdings[grouping_value].to_f + instrument_quantity if instrument_quantity.positive?
        convertibles[grouping_value] = convertibles[grouping_value].to_f + investment.quantity.to_f - instrument_quantity
      end

      next if Array(grouping_value).first.blank?

      instrument_label = self.class.investment_instrument_label(investment)
      instruments_by_group[grouping_value] << instrument_label if instrument_label.present?
    end

    options[:current_holdings] = current_holdings
    options[:convertibles] = convertibles
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
      grouping_value = self.class.shareholder_position_grouping_value(sp, group_by_field)
      next if Array(grouping_value).first.blank?

      latest_position_by_group[grouping_value] = sp
    end

    # Only fold in each group's latest restatement (the same row already selected above for
    # percentage_overrides) - iterating every matching row here would double-count a group that
    # has a snapshot in more than one round within the cumulative funding_rounds window, the same
    # way summing every row's % would.
    latest_position_by_group.each do |grouping_value, sp|
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
      investment = investments.find { |i| self.class.investment_grouping_value(i, group_by_field) == grouping_field }

      # When grouping by :category (alone or as part of a composite key), the category IS part of
      # grouping_field itself (e.g. "Self"), so we can determine is_self directly - this also
      # covers companies whose "Self" holdings come only from ShareholderPosition uploads and have
      # no matching Investment record at all.
      fields = Array(group_by_field).map(&:to_sym)
      values = Array(grouping_field)
      category = fields.include?(:category) ? values[fields.index(:category)] : investment&.category
      label = values[fields.index { |f| %i[category instrument].exclude?(f) } || 0]

      is_self = category == "Self"
      display_name = is_self ? (portfolio_company&.entity&.name || label) : label

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
        category: category,
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

  # The value an Investment is grouped under - a single value for a single group_by_field, or an
  # Array of values (matching the keys ActiveRecord's group(...).sum returns) for a composite one.
  # :instrument is a derived key (see investment_instrument_label), not a column.
  def self.investment_grouping_value(investment, group_by_field)
    values = Array(group_by_field).map do |field|
      field.to_sym == :instrument ? investment_instrument_label(investment) : investment.send(field)
    end
    group_by_field.is_a?(Array) ? values : values.first
  end

  # An Equity investment always shows the literal "Equity" label (it has no instrument_name on
  # the form); a Convertible shows whatever instrument_name was entered for it (nil if blank).
  def self.investment_instrument_label(investment)
    investment.investment_type == "Equity" ? "Equity" : investment.instrument_name.to_s.strip.presence
  end

  # The value a ShareholderPosition is grouped under: its category for :category, its instrument
  # for :instrument, otherwise its investor label (falling back to the linked Investor's name) -
  # an Array for a composite key.
  def self.shareholder_position_grouping_value(shareholder_position, group_by_field)
    values = Array(group_by_field).map do |field|
      case field.to_sym
      when :category then shareholder_position.category
      when :instrument then shareholder_position.instrument.to_s.strip.presence
      else shareholder_position.investor_label.presence || shareholder_position.investor&.investor_name
      end
    end
    group_by_field.is_a?(Array) ? values : values.first
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
