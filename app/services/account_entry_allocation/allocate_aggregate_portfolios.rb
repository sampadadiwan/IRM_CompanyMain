module AccountEntryAllocation
  ############################################################
  # 6. AllocateAggregatePortfolios Operation
  ############################################################
  class AllocateAggregatePortfolios < AllocationBaseOperation
    step :allocate_aggregate_portfolios

    def allocate_aggregate_portfolios(ctx, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula = ctx[:fund_formula]
      start_date   = ctx[:start_date]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      user_id      = ctx[:user_id]

      Rails.logger.debug { "allocate_aggregate_portfolios(#{fund_formula.name})" }

      fund_formula.commitments(end_date, sample).each_with_index do |capital_commitment, idx|
        # This is used to generate instance variables from the cached computed values
        commitment_cache.computed_fields_cache(capital_commitment, start_date)
        apis = fund.aggregate_portfolio_investments

        apis.each do |orig_api|
          ae = AccountEntry.new(
            name: fund_formula.name,
            entry_type: fund_formula.entry_type,
            entity_id: fund.entity_id,
            fund: fund,
            reporting_date: end_date,
            period: "As of #{end_date}",
            generated: true,
            fund_formula: fund_formula
          )

          # We create a "parent" reference
          api = orig_api.as_of(end_date) # aggregator object?
          Rails.logger.debug { "api: #{api}" }

          begin
            create_instance_variables(ctx)
            AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: orig_api, bdg: binding))
          rescue StandardError => e
            Rails.logger.debug e.backtrace
            raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
          end
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
