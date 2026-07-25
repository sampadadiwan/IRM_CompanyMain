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

      # GenerateAccountEntryMultiple: the entry names live inside the formula as an
      # array literal. Precompute the per-name substituted formulas ONCE here — they
      # only depend on the formula text, not on the commitment being processed.
      multiple_name_formulas = nil
      if fund_formula.rule_type == "GenerateAccountEntryMultiple"
        multiple_name_formulas = fund_formula.multiple_entry_names
                                             .zip(fund_formula.multiple_entry_prefixed_names)
                                             .to_h { |entry_name, prefixed_name| [prefixed_name, fund_formula.formula_for_entry_name(entry_name)] }
      end

      ctx[:commitments].each_with_index do |capital_commitment, idx|
        fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

        commitment_cache.computed_fields_cache(capital_commitment, start_date, end_date)

        if multiple_name_formulas
          # One account entry per name, each eval'ed with its own single-name formula
          multiple_name_formulas.each do |prefixed_name, per_name_formula|
            build_account_entry(
              capital_commitment,               # The capital commitment for this entry
              binding,                          # The execution context
              ctx,                              # Additional context
              prefixed_name,                    # e.g. "Quarterly Management Fees"
              formula_override: per_name_formula # Formula with the array replaced by this name
            )
          end
        else
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
        end

        # This is added here to refresh the computed fields after creating multiple account entries
        commitment_cache.computed_fields_cache(capital_commitment, start_date, end_date)

        notify("Completed #{ctx[:formula_index] + 1} of #{ctx[:formula_count]}: #{fund_formula.name} : #{idx + 1} commitments", :success, user_id) if ((idx + 1) % 10).zero?
      end

      true
    end

    def build_account_entry(capital_commitment, bdg, ctx, account_entry_name, formula_override: nil)
      fund = ctx[:fund]
      fund_formula = ctx[:fund_formula]
      end_date = ctx[:end_date]

      # In the metadata if we get multiple account_entry_names, then we add the name_prefix if present
      # example account_entry_names: "Management Fee, Performance Fee", name_prefix: "Quarterly"
      # For GenerateAccountEntryMultiple (formula_override present) the caller has
      # already applied the prefix via multiple_entry_prefix — where meta_data
      # name_prefix acts as the override — so applying it again here would
      # double-prefix the entry name.
      name_prefix = if formula_override
                      ""
                    else
                      fund_formula.meta_data_hash ? (fund_formula.meta_data_hash["name_prefix"] || "") : ""
                    end

      # Initialize a new isolated SQLite record for processing.
      # We use AccountEntrySqlite to ensure high-performance processing without primary DB overhead.
      ae = AccountEntrySqlite.new(
        name: name_prefix + account_entry_name,
        entity_id: fund.entity_id,
        fund_id: fund.id,
        reporting_date: end_date,
        period: "As of #{end_date}",
        entry_type: fund_formula.entry_type,
        generated: true,
        cumulative: false,
        fund_formula_id: fund_formula.id,
        rule_for: fund_formula.rule_for
      )

      begin
        # Setup the dynamic variables required for formula evaluation
        create_instance_variables(ctx)

        # Call the sub-operation to finalize the account entry creation.
        # This will evaluate the formula and save the 'ae' record to the isolated SQLite DB.
        AccountEntryAllocation::CreateAccountEntry.call(
          ctx.merge(
            account_entry: ae,
            capital_commitment: capital_commitment,
            parent: nil,
            bdg:,
            # nil for all rule types except GenerateAccountEntryMultiple, where it
            # carries the per-name substituted formula to be eval'ed instead of
            # fund_formula.formula
            formula_override:
          )
        )
      rescue StandardError => e
        Rails.logger.debug e.backtrace
        # Provide detailed error context, handling cases where capital_commitment might be nil
        msg = "Error in #{fund_formula.name}:#{fund_formula.id}"
        msg += " for #{capital_commitment}" if capital_commitment.present?
        raise "#{msg}: #{e.message}"
      end
    end
  end
end
