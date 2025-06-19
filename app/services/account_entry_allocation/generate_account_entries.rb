module AccountEntryAllocation
  ############################################################
  # 9. GenerateAccountEntries Operation
  ############################################################
  class GenerateAccountEntries < AllocationBaseOperation
    step :generate_account_entries

    def generate_account_entries(ctx, **)
      fund_formula = ctx[:fund_formula]
      commitment_cache = ctx[:commitment_cache]
      fund          = ctx[:fund]
      start_date    = ctx[:start_date]
      end_date      = ctx[:end_date]
      sample        = ctx[:sample]
      user_id       = ctx[:user_id]

      Rails.logger.debug { "generate_account_entries(#{fund_formula.name}, #{fund_formula.formula})" }

      fund_unit_settings = FundUnitSetting.where(fund_id: fund.id).index_by(&:name)
      # Sometimes the same fund formula is used to generate for multiple account entry names
      account_entry_names = fund_formula.meta_data_hash["account_entry_names"]&.split(",")&.map(&:strip) if fund_formula.meta_data_hash.present?

      fund_formula.commitments(end_date, sample).includes(:entity, :fund).each_with_index do |capital_commitment, idx|
        fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]
        fields = commitment_cache.computed_fields_cache(capital_commitment, start_date)

        # Determine the list of account entry names to process
        # If `account_entry_names` is present, use it as-is
        # Otherwise, default to using the fund_formula's name
        entry_names = account_entry_names.presence || [fund_formula.name]

        # Iterate over the resolved entry names and build account entries
        entry_names.each do |account_entry_name|
          build_account_entry(
            capital_commitment,  # The capital commitment for this entry (can be nil)
            binding,             # The execution context
            ctx,                 # Additional context
            account_entry_name   # The name to tag the account entry with
          )
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end

    def build_account_entry(capital_commitment, bdg, ctx, account_entry_name)
      fund = ctx[:fund]
      fund_formula = ctx[:fund_formula]
      end_date = ctx[:end_date]

      # In the metadata if we get multiple account_entry_names, then we add the name_prefix if present
      # example account_entry_names: "Management Fee, Performance Fee", name_prefix: "Quarterly"
      name_prefix = fund_formula.meta_data_hash ? (fund_formula.meta_data_hash["name_prefix"] || "") : ""

      ae = AccountEntry.new(name: name_prefix + account_entry_name, entity_id: fund.entity_id, fund: fund, reporting_date: end_date, period: "As of #{end_date}", entry_type: fund_formula.entry_type, generated: true, cumulative: false, fund_formula: fund_formula, rule_for: fund_formula.rule_for)

      begin
        create_instance_variables(ctx)
        AccountEntryAllocation::CreateAccountEntry.call(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: nil, bdg:))
      rescue StandardError => e
        raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
      end
    end
  end
end
