module AccountEntryAllocation
  ############################################################
  # GenerateFinancialStatementLines Operation
  # Once per fund (like GeneratePortfolioNumbersForFund): computes the fund's statement-account
  # figures from its statement mapping and writes them as fund-level "Financial Statement" entries
  # dated the statement end date, three per account:
  #   movement account: "FS · <account>" (period), "FS · YTD <account>" (ytd), "FS · Since Inception <account>" (balance)
  #   balance account:  "FS · <account>" (balance), "FS · Opening <account>" (opening), "FS · YTD Opening <account>" (ytd_opening)
  # The "FS · " prefix keeps them from ever sharing a name with the fund's own entries, which fund ratios
  # and document templates look up by name; the statements themselves print the plain account label.
  # json_fields {fs_account_id, column} let FinancialStatement#figures read them back.
  #
  # The run's own dates are the statement end date only (FinancialStatementGenerate), so the engine's
  # delete step removes only lines on that date; the real period start comes from the statement set
  # this run belongs to. The calculator reads the live database, not the scratch SQLite, because an
  # incremental fund's scratch copy holds only recent entries (card ④ —
  # openspec/changes/fund-financial-statements/design.md#④-statements-run).
  # Worked examples H12, H13, E16, X11 — openspec/changes/fund-financial-statements/design.md#worked-examples
  ############################################################
  class GenerateFinancialStatementLines < AllocationBaseOperation
    step :generate_lines

    def generate_lines(ctx, **)
      fund = ctx[:fund]
      fund_formula = ctx[:fund_formula]
      end_date = ctx[:end_date]
      # The statement set this run belongs to gives the real period start (run dates are the end date only)
      statement = FinancialStatement.find_by(statements_allocation_run_id: ctx[:allocation_run_id]) if ctx[:allocation_run_id]
      start_date = statement&.start_date || ctx[:start_date]

      # Figures for every account, from the live database. H13: this op writes only
      # "Financial Statement" entries — no accounting entry is read for writing or changed
      result = FinancialStatementCalculator.call(fund:, start_date:, end_date:)
      accounts = FinancialStatementAccount.where(fund_id: fund.id).index_by(&:id)
      now = Time.zone.now

      records = result.figures.flat_map do |account_id, figures|
        account = accounts[account_id]
        # An account deleted mid-run writes nothing
        next [] unless account

        entry_specs(account).map do |name, column, cumulative|
          { "entity_id" => fund.entity_id, "fund_id" => fund.id, "entry_type" => FinancialStatementCalculator::FS_ENTRY_TYPE,
            "name" => name, "reporting_date" => end_date, "period" => "As of #{end_date}", "amount_cents" => figures[column],
            "cumulative" => cumulative, "generated" => true, "fund_formula_id" => fund_formula.id,
            "allocation_run_id" => ctx[:allocation_run_id], "rule_for" => "Accounting",
            "explanation" => ["Statement account #{account.name} (#{column}) from the fund's statement mapping, #{start_date} to #{end_date}"],
            "json_fields" => { "fs_account_id" => account.id, "column" => column },
            "created_at" => now, "updated_at" => now }
        end
      end

      # E16: the engine's delete step already removed this formula's earlier lines on the end date.
      # BulkInsertData (called by RunFormula after this op) inserts these into the scratch DB and the
      # engine migrates them to primary. Appended in place: RunFormula reads the same array back.
      ctx[:bulk_insert_records].concat(records)
      true
    rescue StandardError => e
      raise "Error in #{fund_formula&.name}:#{fund_formula&.id} for #{fund}: #{e.message}"
    end

    private

    # [name, figure column, cumulative?] for each entry an account gets
    def entry_specs(account)
      prefix = FinancialStatementCalculator::FS_NAME_PREFIX
      if account.behaviour == "movement"
        [["#{prefix}#{account.name}", "period", false], ["#{prefix}YTD #{account.name}", "ytd", false],
         ["#{prefix}Since Inception #{account.name}", "balance", true]]
      else
        [["#{prefix}#{account.name}", "balance", true], ["#{prefix}Opening #{account.name}", "opening", true],
         ["#{prefix}YTD Opening #{account.name}", "ytd_opening", true]]
      end
    end
  end
end
