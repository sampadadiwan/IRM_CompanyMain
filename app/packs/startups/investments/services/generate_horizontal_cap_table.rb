class GenerateHorizontalCapTable < Trailblazer::Operation
  step :initialize_params
  step :fetch_metadata
  step :initialize_table_data
  step :process_rounds
  step :merge_shareholder_positions
  step :format_result

  def initialize_params(options, params:, **)
    options[:portfolio_company_id] = params[:portfolio_company_id]
  end

  def fetch_metadata(options, portfolio_company_id:, **)
    investments = Investment.where(portfolio_company_id: portfolio_company_id)
    options[:all_investments] = investments.to_a # Fetch everything once to avoid N+1
    options[:all_funding_rounds] = investments.order(investment_date: :asc).pluck(:funding_round).uniq
    options[:all_investors] = investments.select(:investor_name, :category).distinct.to_a

    portfolio_company = Investor.find(portfolio_company_id)
    options[:portfolio_company] = portfolio_company
    options[:portfolio_company_name] = portfolio_company.entity.name
  end

  def initialize_table_data(options, all_investors:, portfolio_company_name:, **)
    # Replace investor_name with portfolio_company_name for "Self" records in the grouping
    investors = all_investors.map do |i|
      name = i.category == "Self" ? portfolio_company_name : i.investor_name
      OpenStruct.new(investor_name: name, display_name: name, category: i.category)
    end

    options[:investors_by_category] = investors.group_by(&:category)
    options[:table_data] = {}
    options[:round_data] = {}
  end

  def process_rounds(options, all_funding_rounds:, portfolio_company_id:, all_investors:, table_data:, round_data:, **)
    cumulative_rounds = []

    all_funding_rounds.each do |round|
      cumulative_rounds << round

      result = GenerateCapTable.call(params: {
                                       funding_rounds: cumulative_rounds,
                                       portfolio_company_id: portfolio_company_id
                                     })

      cap_round = result[:model]
      next if cap_round.blank?

      # Extract total for this round
      total_row = cap_round.find { |r| r[:grouping_field] == "Total" }
      round_data[round] = {
        total_equity: total_row[:quantity],
        total_fully_diluted: total_row[:fully_diluted],
        # Investment-driven fully diluted totals are always real share/unit quantities.
        fully_diluted_is_quantity: true
      }

      # Fill table_data
      cap_round.each do |row|
        next if row[:grouping_field] == "Total"

        # Special handling for "Self"
        if row[:is_self] || row[:grouping_field] == options[:portfolio_company_name]
          category = "Self"
          investor_name = options[:portfolio_company_name]
        else
          # Find investor to get category
          investor = all_investors.find { |i| i.investor_name == row[:grouping_field] }
          if investor
            category = investor.category
            investor_name = investor.investor_name
          else
            next
          end
        end

        table_data[category] ||= {}
        table_data[category][investor_name] ||= {}
        table_data[category][investor_name][round] = {
          fully_diluted_percentage: row[:fully_diluted_percentage],
          quantity: row[:quantity],
          fully_diluted: row[:fully_diluted]
        }
      end
    end
  end

  def merge_shareholder_positions(_options, portfolio_company_id:, all_funding_rounds:, investors_by_category:, table_data:, round_data:, **)
    positions = ShareholderPosition
                .approved
                .where(portfolio_company_id: portfolio_company_id)
                .where.not(position_amount: nil)
                .includes(:investor)
                .order(created_at: :asc, id: :asc)

    return true if positions.blank?

    upload_name_by_id = ImportUpload.where(id: positions.map(&:import_upload_id).compact.uniq).pluck(:id, :name).to_h
    grouped_snapshots = positions.group_by { |sp| [sp.import_upload_id, sp.round_name.presence || sp.position_date&.to_date] }

    # An investor holding more than one distinct instrument (e.g. an Equity stake and a
    # separate CCPS stake) is shown as separate rows, one per instrument, rather than blended
    # into a single combined percentage/quantity - so the "(Instrument)" suffix below is only
    # ever added for investors who actually have multiple instruments; an investor who only
    # ever uploads a single instrument keeps their existing plain row (no redundant suffix,
    # since the Instrument column already shows it).
    instruments_by_investor = Hash.new { |h, k| h[k] = Set.new }
    positions.each do |sp|
      name = sp.investor_label.presence || sp.investor&.investor_name
      next if name.blank? || sp.instrument.blank?

      instruments_by_investor[name] << sp.instrument.strip
    end
    multi_instrument_investors = instruments_by_investor.select { |_, insts| insts.size > 1 }.keys.to_set

    grouped_snapshots.each_value do |snapshot|
      next if snapshot.blank?

      import_upload_id = snapshot.first.import_upload_id
      position_date = snapshot.first.position_date
      round_name = snapshot.first.round_name

      raise "As Of is required for each shareholder position row. Missing position_date/round_name for import_upload=#{import_upload_id}." if position_date.blank? && round_name.blank?

      # A free-text round name (e.g. "Secondary Sale") is used directly as the round label,
      # bypassing month/year matching entirely. Only a real As Of date goes through the
      # month/year -> existing funding round matching below.
      round_label = if round_name.present?
                      round_name
                    else
                      as_of_month_year = position_date.strftime("%B %Y")
                      matching_round_for_month_year(all_funding_rounds, as_of_month_year) || as_of_month_year
                    end
      all_funding_rounds << round_label unless all_funding_rounds.include?(round_label)

      # The same investor + instrument combination can appear more than once in one upload for
      # the same round (e.g. a row pasted twice, or a correction row added after the original) -
      # these are not two separate additive lots, the later row entirely supersedes the earlier
      # one. Only the latest row (by upload order) for each investor+instrument combo is kept,
      # both for that investor's own displayed amount and for the round's grand total used to
      # compute every other investor's percentage.
      deduped_snapshot = snapshot.group_by { |sp| [sp.investor_label.presence || sp.investor&.investor_name, sp.instrument.to_s.strip] }
                                  .values.map(&:last)

      raw_total = deduped_snapshot.sum { |sp| sp.position_amount.to_f }
      treat_as_fraction = raw_total.positive? && raw_total <= 1.5
      normalized_total = treat_as_fraction ? (raw_total * 100.0) : raw_total
      treat_as_percent = normalized_total.positive? && normalized_total <= 100.5

      deduped_snapshot.each do |sp|
        base_investor_name = sp.investor_label.presence || sp.investor&.investor_name
        next if base_investor_name.blank?

        # Give this investor a distinct row per instrument only when they actually hold more
        # than one - e.g. "Iron Pillar (CCPS)" and "Iron Pillar (Equity)" as two separate rows -
        # instead of silently blending both instruments' amounts into one row. The suffix is only
        # used internally as the table_data/investors_by_category key so the two rows don't
        # collide - the rendered Particulars column shows the plain `display_name` below, with
        # the instrument itself shown separately in the Instrument column.
        investor_name = base_investor_name
        investor_name = "#{base_investor_name} (#{sp.instrument.strip})" if sp.instrument.present? && multi_instrument_investors.include?(base_investor_name)

        category = sp.category.presence || category_for_investor(investors_by_category, investor_name) || "Other"
        subgroup_label = sp.subgroup.to_s.strip.presence

        # An investor may already be bucketed under a different category (e.g. from
        # Investment funding rounds, which use a separate fixed category list). Move
        # them into this ShareholderPosition's category instead of duplicating them
        # across two categories in the rendered cap table.
        relocate_investor_category(investors_by_category, table_data, investor_name, category)

        investors_by_category[category] ||= []
        existing_investor = investors_by_category[category].find { |inv| inv.investor_name == investor_name }
        if existing_investor.nil?
          investors_by_category[category] << OpenStruct.new(
            investor_name: investor_name,
            display_name: base_investor_name,
            category: category,
            subgroup: subgroup_label
          )
        elsif existing_investor.subgroup.blank? && subgroup_label.present?
          existing_investor.subgroup = subgroup_label
        end

        table_data[category] ||= {}
        table_data[category][investor_name] ||= {}
        existing = table_data[category][investor_name][round_label] || {}

        amount = sp.position_amount.to_f
        normalized_amount = treat_as_fraction ? (amount * 100.0) : amount

        # Duplicates for this exact investor+instrument were already collapsed to the latest
        # row above, so this is simply that row's own amount/percentage - not added to whatever
        # (now-superseded) value may have been present before.
        #
        # A real, persisted Fully Diluted % on the row (typed in at upload time) is always used
        # as-is - it's only ever derived from the Fully Dilluted Quantity at upload time when the
        # row didn't have a % typed in for it (see ImportShareholderPosition#save_row), so it's
        # already the most trustworthy value available. Only fall back to computing % from this
        # round's quantities here when the row has no persisted % at all.
        fd_percent = if sp.fully_diluted_percentage.present?
                       sp.fully_diluted_percentage.to_f
                     elsif treat_as_percent
                       normalized_amount
                     elsif normalized_total.positive?
                       (normalized_amount / normalized_total * 100.0)
                     else
                       0.0
                     end

        # "Quantity Actuals" is an optional upload column - a real (non fully-diluted) share/unit
        # count for the row. When omitted, the quantity stays whatever it already was (0 unless an
        # Investment-driven round already populated it), so the "Quantity actual" column in the
        # cap table can be auto-hidden rather than showing a column of all zeros.
        quantity_value = sp.quantity_actual.present? ? sp.quantity_actual.to_f : (existing[:quantity] || 0)

        table_data[category][investor_name][round_label] = existing.merge(
          fully_diluted_percentage: "#{fd_percent.round(1)}%",
          quantity: quantity_value,
          fully_diluted: normalized_amount,
          instrument: sp.instrument.presence || existing[:instrument],
          # Recorded so carry_forward_position_holdings can tell whether a later round that's
          # missing this investor came from the very same upload batch (a deliberate omission -
          # e.g. they exited/converted out) versus a genuinely separate, later upload that simply
          # never mentioned them (a reporting gap - still assume they continue holding).
          import_upload_id: import_upload_id
        )
      end


      snapshot_quantity_actual_total = deduped_snapshot.sum { |sp| sp.quantity_actual.to_f }
      round_data[round_label] ||= {
        total_equity: round_data.dig(round_label, :total_equity) || snapshot_quantity_actual_total,
        total_fully_diluted: round_data.dig(round_label, :total_fully_diluted) || (treat_as_percent ? 100.0 : normalized_total)
      }
      # Only a snapshot whose amounts were interpreted as real quantities (not a bare
      # percentage) proves this round has genuine "Quantity- fully diluted" data. Once any
      # snapshot (or an Investment-driven round in process_rounds) has proven it, never
      # downgrade it back to false for a later percent-only snapshot on the same round.
      round_data[round_label][:fully_diluted_is_quantity] ||= !treat_as_percent
    end

    carry_forward_position_holdings(all_funding_rounds, table_data, round_data)

    true
  end

  # A ShareholderPosition tagged to one round (e.g. a one-time Founders upload booked under a
  # "Founding" round rather than a snapshot date) should keep counting toward every later
  # round's fully diluted quantity, the same way real equity/convertible holdings never
  # disappear from later Investment funding rounds. Without this, an investor whose only
  # entry is on an earlier round shows a 100% stake on that round's own column, but 0 in the
  # "Quantity- fully diluted (latest round)" total simply because they have no row recorded
  # for the latest round.
  #
  # This only fills gaps (rounds where the investor has no entry of their own) and adds the
  # carried amount on top of round_data's existing total, so already-correct Investment-driven
  # round totals are never recomputed or overwritten - only topped up with the carried amount.
  def carry_forward_position_holdings(all_funding_rounds, table_data, round_data)
    # A carried-forward cell's percentage can't be computed until round_data[round]'s total is
    # final - and that total keeps growing as every other investor's carry-forward for the same
    # round is folded in below - so gap cells are collected here and their percentage is
    # backfilled in a second pass once every investor has been processed.
    carried_cells = []

    # A round is only a genuine "reporting gap" for a given investor if the upload that last
    # recorded their holding never actually covered this round. If that SAME upload batch
    # already contributed real rows to this round (e.g. one Excel with several "As Of" dates/
    # rounds that relists every other investor), a missing row here means the file deliberately
    # left this investor out - most likely they exited/converted out by then - so their holding
    # must NOT be carried forward into it.
    upload_ids_by_round = Hash.new { |h, k| h[k] = Set.new }
    table_data.each_value do |investors|
      investors.each_value do |rounds_data|
        rounds_data.each do |round, entry|
          upload_ids_by_round[round] << entry[:import_upload_id] if entry.present? && entry[:import_upload_id].present?
        end
      end
    end

    table_data.each_value do |investors|
      investors.each_value do |rounds_data|
        last_quantity = nil
        last_fully_diluted = nil
        last_import_upload_id = nil

        all_funding_rounds.each do |round|
          entry = rounds_data[round]

          if entry.present?
            last_quantity = entry[:quantity] if entry[:quantity].present?
            last_fully_diluted = entry[:fully_diluted] if entry[:fully_diluted].present?
            last_import_upload_id = entry[:import_upload_id] if entry[:import_upload_id].present?
            next
          end

          next if last_quantity.blank? && last_fully_diluted.blank?
          next if last_import_upload_id.present? && upload_ids_by_round[round].include?(last_import_upload_id)

          carried_quantity = last_quantity || 0
          carried_fully_diluted = last_fully_diluted || 0

          rounds_data[round] = {
            fully_diluted_percentage: "0.0%",
            quantity: carried_quantity,
            fully_diluted: carried_fully_diluted,
            # Marks this cell as synthesized (no real upload/Investment record for this
            # investor in this specific round) so the "latest round" Quantity Actual/Fully
            # Diluted columns - which only ever show the single latest_round cell - can render
            # an empty "-" for this investor instead of a carried-forward number that could be
            # mistaken for real data uploaded for that round. The Instrument column falls back
            # to "-" the same way for these cells - every real uploaded row always defines its
            # own instrument, so there's nothing to carry forward here.
            carried_forward: true
          }
          carried_cells << { round: round, entry: rounds_data[round] }

          round_data[round] ||= { total_equity: 0, total_fully_diluted: 0 }
          round_data[round][:total_equity] = round_data[round][:total_equity].to_f + carried_quantity.to_f
          round_data[round][:total_fully_diluted] = round_data[round][:total_fully_diluted].to_f + carried_fully_diluted.to_f
        end
      end
    end

    # Now that round_data[round][:total_fully_diluted] reflects every carried contribution for
    # that round, replace the placeholder "0.0%" with the investor's real share of that final
    # total - previously this stayed 0.0% forever, understating (to 0) the stake of any investor
    # whose only real entry was on an earlier round, even though their quantity/fully_diluted
    # values - and the round's grand total - already correctly included their holding.
    carried_cells.each do |cell|
      total = round_data.dig(cell[:round], :total_fully_diluted).to_f
      next unless total.positive?

      cell[:entry][:fully_diluted_percentage] = "#{(cell[:entry][:fully_diluted].to_f / total * 100).round(1)}%"
    end
  end

  def category_for_investor(investors_by_category, investor_name)
    investors_by_category.each do |category, investors|
      return category if investors.any? { |inv| inv.investor_name == investor_name }
    end
    nil
  end

  # Moves an investor's entry (and any table_data already recorded for them) out of
  # whichever category they currently live in and into `new_category`, so the same
  # investor never appears twice in the cap table under two different categories.
  def relocate_investor_category(investors_by_category, table_data, investor_name, new_category)
    old_category = investors_by_category.find do |cat, investors|
      cat != new_category && investors.any? { |inv| inv.investor_name == investor_name }
    end&.first

    return if old_category.nil?

    moved_investor = investors_by_category[old_category].find { |inv| inv.investor_name == investor_name }
    investors_by_category[old_category].delete(moved_investor)
    investors_by_category.delete(old_category) if investors_by_category[old_category].empty?
    moved_investor.category = new_category

    investors_by_category[new_category] ||= []
    investors_by_category[new_category] << moved_investor

    return unless table_data[old_category]&.key?(investor_name)

    table_data[new_category] ||= {}
    table_data[new_category][investor_name] = table_data[old_category].delete(investor_name).merge(
      table_data[new_category][investor_name] || {}
    )
    table_data.delete(old_category) if table_data[old_category].empty?
  end

  def matching_round_for_month_year(rounds, month_year)
    return nil if month_year.blank?

    exact_match = rounds.find { |round| round.to_s.strip == month_year }
    return exact_match if exact_match.present?

    rounds.find do |round|
      normalized = normalize_round_month_year(round)
      normalized.present? && normalized == month_year
    end
  end

  def normalize_round_month_year(round_label)
    return nil if round_label.blank?

    cleaned = round_label.to_s.strip.sub(/\Aas\s*of\s*/i, "").strip
    return nil if cleaned.blank?

    # Only treat a round label as a canonical month-year when it is exactly the month name and year.
    # This prevents labels like 'Secondary Jan 2025' or 'Series A' from being mistaken for an As Of period.
    return cleaned if cleaned.match?(/\A(?:January|February|March|April|May|June|July|August|September|October|November|December)\s+\d{4}\z/i)

    nil
  end

  # rubocop:enable Metrics/BlockLength

  def format_result(options, all_funding_rounds:, investors_by_category:, table_data:, round_data:, **)
    options[:model] = {
      funding_rounds: all_funding_rounds,
      categories: investors_by_category.keys.sort,
      investors_by_category: investors_by_category,
      table_data: table_data,
      round_data: round_data
    }
  end
end
