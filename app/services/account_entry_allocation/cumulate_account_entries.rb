module AccountEntryAllocation
  ############################################################
  # 11. CumulateAccountEntries Operation
  ############################################################
  class CumulateAccountEntries < AllocationBaseOperation
    step :cumulate_account_entries

    def cumulate_account_entries(ctx, **)
      fund_formula = ctx[:fund_formula]
      commitment_cache = ctx[:commitment_cache]
      end_date     = ctx[:end_date]
      sample       = ctx[:sample]
      start_date   = ctx[:start_date]

      bulk_records = []

      fund_formula.commitments(end_date, sample).includes(:entity, :fund, :investor_kyc).find_each do |capital_commitment|
        Rails.logger.debug { "Cumulating #{fund_formula} to #{capital_commitment}" }
        next unless fund_formula.roll_up

        cumulative_ae = capital_commitment.rollup_account_entries(
          fund_formula.name,
          fund_formula.entry_type,
          start_date,
          end_date
        )

        # Since this is a rollup, we set the rule_for to reporting
        cumulative_ae.rule_for = "reporting"

        bulk_records << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
        commitment_cache.add_to_computed_fields_cache(capital_commitment, cumulative_ae)
      end

      if bulk_records.present?
        count = AccountEntry.insert_all(bulk_records)
        Rails.logger.debug { "#{fund_formula.name}: Inserted #{count} roll_up records" }
      end

      true
    end
  end
end
