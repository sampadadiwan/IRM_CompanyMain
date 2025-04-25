module AccountEntryAllocation
  ############################################################
  # 12. AllocateMasterFundAccountEntries Operation
  ############################################################
  # The AllocateMasterFundAccountEntries class is responsible for allocating master fund account entries
  # based on exchange rates and fund formulas. It inherits from AllocationBaseOperation and defines two
  # main steps: get_exchange_rate and allocate_master_fund_account_entries.
  #
  # Steps:
  # 1. get_exchange_rate: Retrieves the exchange rate between the master fund's currency and the fund's currency.
  #    If no exchange rate is found, it logs an error and raises an exception.
  # 2. allocate_master_fund_account_entries: Allocates account entries for the master fund based on the provided
  #    fund formula, start and end dates, and other parameters. It generates account entries to allocate to the
  #    commitments of the feeder fund and handles any errors that occur during the allocation process.
  #
  # Methods:
  # - get_exchange_rate: Retrieves the exchange rate for the given fund.
  # - allocate_master_fund_account_entries: Allocates master fund account entries based on the fund formula and
  #   other parameters.
  # - generate_account_entry_to_allocate: Generates an account entry to allocate to the commitments of the feeder fund.
  class AllocateMasterFundAccountEntries < AllocationBaseOperation
    step :get_exchange_rate
    step :allocate_master_fund_account_entries

    def get_exchange_rate(ctx, fund:, end_date:, **)
      if fund.master_fund.currency != fund.currency
        # Possibly exchange rate conversions, etc.
        exchange_rate = fund.entity.exchange_rates.where(
          from: fund.master_fund.currency,
          to: fund.currency
        ).where(as_of: ..end_date).order(as_of: :asc).last

        if exchange_rate.blank?
          msg = "No exchange rate found for #{fund.master_fund.currency} to #{fund.currency}"
          ctx[:error] = msg
          Rails.logger.error { msg }
          raise msg
        end

        ctx[:exchange_rate] = exchange_rate
      end
      true
    end

    def allocate_master_fund_account_entries(ctx, fund:, fund_formula:, start_date:, end_date:, name_or_entry_type:, **)
      commitment_cache = ctx[:commitment_cache]
      sample        = ctx[:sample]
      user_id       = ctx[:user_id]

      Rails.logger.debug { "allocate_master_fund_account_entries #{fund_formula.name}" }

      # Get the master fund account entries for the given fund formula, grouped by folio_id
      master_fund_account_entries = fund.master_fund.account_entries.not_cumulative.joins(capital_commitment: :feeder_fund).where("funds.id = ? and account_entries.name = ?", fund.id, fund_formula.name).where(reporting_date: start_date..end_date)

      # This may be used inside the fund formula
      master_fund_account_entries_by_folio = master_fund_account_entries.group_by(&:folio_id).transform_values { |entries| entries.sum(&:amount_cents) }

      Rails.logger.debug { "master_fund_account_entries_by_folio has #{master_fund_account_entries_by_folio.length} entries" }

      fund_formula.commitments(end_date, sample).each_with_index do |capital_commitment, idx|
        Rails.logger.debug { "Processing commitment #{capital_commitment.id} for #{fund_formula.name}" }

        master_aggregate_entry, feeder_aggregate_entry = generate_account_entry_to_allocate(fund_formula, start_date, end_date)
        commitment_cache.computed_fields_cache(capital_commitment, start_date)
        exchange_rate = ctx[:exchange_rate]

        # We need to pass an account_entry into the CreateAccountEntry operation
        account_entry = feeder_aggregate_entry.dup

        Rails.logger.debug { "Processing commitment #{capital_commitment.id} for #{fund_formula.name} with feeder amount #{feeder_aggregate_entry.amount_cents} and master amount #{master_aggregate_entry.amount_cents}" }

        begin
          create_instance_variables(ctx)
          AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry:, capital_commitment: capital_commitment, parent: nil, bdg: binding))
        rescue StandardError => e
          raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end

    # Generates an aggregated account entry for allocation based on the provided fund formula, date range, and exchange rate. We have account_entries in the master fund that are allocated to commitments of the feeder fund. We need to aggregate these account entries and add the feeder fund's account entries to get the total amount to allocate to the commitments.

    # @param fund_formula [FundFormula] The formula containing fund and allocation details.
    # @param start_date [Date] The start date for the account entry allocation period.
    # @param end_date [Date] The end date for the account entry allocation period.
    # @param exchange_rate [ExchangeRate] The exchange rate to convert amounts to the feeder fund's currency.
    # @return [AccountEntry] The aggregated account entry for the specified period and fund formula.
    def generate_account_entry_to_allocate(fund_formula, start_date, end_date)
      # Get the fund and its master fund
      fund = fund_formula.fund
      master_fund = fund.master_fund

      # Fetch all account entries in the master fund allocated to commitments of the feeder fund
      master_fund_account_entries = master_fund.account_entries.not_cumulative.joins(capital_commitment: :feeder_fund)
                                               .where("funds.id = ? and account_entries.name = ?", fund.id, fund_formula.name)
                                               .where(reporting_date: start_date..end_date)

      # Create a new AccountEntry object to aggregate the master fund account entries
      master_aggregate_entry = AccountEntry.new(
        name: fund_formula.name,
        reporting_date: end_date,
        cumulative: false,
        rule_for: fund_formula.rule_for,
        fund_id: master_fund.id,
        entity_id: fund_formula.entity_id
      )

      if master_fund_account_entries.present?
        # Sum the amounts of all account entries in the master fund with this name
        # Convert the amount to the currency of the feeder fund using the exchange rate
        master_aggregate_entry.entry_type = fund_formula.entry_type
        master_aggregate_entry.json_fields = master_fund_account_entries.first.json_fields
        master_aggregate_entry.amount_cents = master_fund_account_entries.sum(:amount_cents)
      else
        # If no account entries are present, set the amount to 0
        master_aggregate_entry.amount_cents = 0
      end

      # Aggregate the account entries in the feeder fund to be allocated to the commitments
      feeder_account_entries = fund.account_entries.fund_entries.where(
        reporting_date: start_date..end_date,
        name: fund_formula.name
      )
      feeder_amount_cents = feeder_account_entries.sum(:amount_cents)

      feeder_aggregate_entry = AccountEntry.new(
        name: fund_formula.name,
        reporting_date: end_date,
        cumulative: false,
        rule_for: fund_formula.rule_for,
        fund_id: fund_formula.fund_id,
        entity_id: fund_formula.entity_id
      )

      # Add the feeder fund amount to the master fund aggregate amount
      feeder_aggregate_entry.amount_cents = feeder_amount_cents
      feeder_aggregate_entry.entry_type = fund_formula.entry_type
      # Return the aggregated account entry
      [master_aggregate_entry, feeder_aggregate_entry]
    end
  end
end
