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

      fund_formula.commitments(end_date, sample).each_with_index do |capital_commitment, idx|
        fields = commitment_cache.computed_fields_cache(capital_commitment, start_date)
        ae = AccountEntry.new(
          name: fund_formula.name,
          entity_id: fund.entity_id,
          fund: fund,
          reporting_date: end_date,
          period: "As of #{end_date}",
          entry_type: fund_formula.entry_type,
          generated: true,
          cumulative: false,
          fund_formula: fund_formula
        )

        fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

        begin
          create_instance_variables(ctx)
          AccountEntryAllocation::CreateAccountEntry.wtf?(ctx.merge(account_entry: ae, capital_commitment: capital_commitment, parent: nil, bdg: binding))
        rescue StandardError => e
          raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
        end

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
