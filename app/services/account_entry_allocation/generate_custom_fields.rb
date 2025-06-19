module AccountEntryAllocation
  ############################################################
  # 4. GenerateCustomFields Operation
  ############################################################
  class GenerateCustomFields < AllocationBaseOperation
    step :generate_custom_fields

    def generate_custom_fields(ctx, **)
      fund_formula = ctx[:fund_formula]
      commitment_cache = ctx[:commitment_cache]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      start_date   = ctx[:start_date]
      user_id      = ctx[:user_id]
      fund_unit_settings = FundUnitSetting.where(fund_id: ctx[:fund].id).index_by(&:name)

      Rails.logger.debug { "generate_custom_fields #{fund_formula.name}" }

      fund_formula.commitments(end_date, sample).includes(:entity, :fund).each_with_index do |capital_commitment, idx|
        # Possibly retrieve the relevant FundUnitSetting for each commitment
        fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

        Rails.logger.debug { "Generating using formula #{fund_formula} for #{capital_commitment}, #{start_date}, #{end_date}, #{fund_unit_setting}" }

        ae = AccountEntry.new(
          name: fund_formula.name,
          fund_formula: fund_formula,
          amount_cents: safe_eval(fund_formula.formula, binding)
        )

        commitment_cache.add_to_computed_fields_cache(capital_commitment, ae)

        # This triggers any internal caching/notifications
        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end
  end
end
