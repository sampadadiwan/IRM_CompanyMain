module AccountEntryAllocation
  ############################################################
  # 12. AllocateMasterFundAccountEntries Operation
  ############################################################
  class AllocateMasterFundAccountEntries < AllocationBaseOperation
    step :allocate_master_fund_account_entries

    def allocate_master_fund_account_entries(ctx, name_or_entry_type:, **)
      fund = ctx[:fund]
      commitment_cache = ctx[:commitment_cache]
      fund_formula  = ctx[:fund_formula]
      start_date    = ctx[:start_date]
      end_date      = ctx[:end_date]
      sample        = ctx[:sample]
      user_id       = ctx[:user_id]

      Rails.logger.debug { "allocate_master_fund_account_entries #{fund_formula.name}" }

      master_fund_account_entries_cache = {}

      fund_formula.commitments(end_date, sample).each_with_index do |capital_commitment, idx|
        master_fund_account_entry = master_fund_account_entries_cache[capital_commitment.unit_type]

        if master_fund_account_entry.blank?
          # find the commitment_in_master
          commitment_in_master = capital_commitment.fund.commitments_in_master
                                                   .where(unit_type: capital_commitment.unit_type)
                                                   .first
          # get the associated account entry from the master fund
          master_fund_account_entry = commitment_in_master.account_entries.where(
            name: fund_formula.name,
            reporting_date: start_date..end_date,
            cumulative: false,
            commitment_type: fund_formula.commitment_type
          ).first

          master_fund_account_entries_cache[capital_commitment.unit_type] = master_fund_account_entry
        end

        Rails.logger.debug { "Allocating #{master_fund_account_entry} to #{capital_commitment}" }

        commitment_cache.computed_fields_cache(capital_commitment, start_date)

        # Create a local copy to insert
        ae = master_fund_account_entry.dup
        ae.fund_id   = fund.id
        ae.entity_id = fund.entity_id

        # Possibly exchange rate conversions, etc.
        exchange_rate = fund.entity.exchange_rates.where(
          from: fund.master_fund.currency,
          to: fund.currency
        ).latest.last

        begin
          create_instance_variables(ctx)
          AccountEntryAllocation::CreateAccountEntry.wtf?(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: master_fund_account_entry, bdg: binding))
        rescue StandardError => e
          raise "Error in #{fund_formula.name} for #{capital_commitment} #{master_fund_account_entry}: #{e.message}"
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
