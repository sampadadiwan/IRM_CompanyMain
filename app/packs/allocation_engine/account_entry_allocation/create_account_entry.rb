module AccountEntryAllocation
  ############################################################
  # 8. CreateAccountEntry Operation
  ############################################################
  class CreateAccountEntry < AllocationBaseOperation
    step :init
    step :create_account_entry
    step :add_account_entry_value_to_binding
    step :create_quarterly_account_entry
    step :create_ytd_account_entry
    step :create_since_inception_account_entry

    ADDITONAL_AE = ["Quarterly", "YTD", "Since Inception"].freeze

    def init(ctx, account_entry:, **)
      @variable_name = to_varable_name(account_entry.name)
      # Ensure all the instance variables needed for the formla are instansiated
      create_instance_variables(ctx)
      @skip_rule = false
      true
    end

    def create_account_entry(ctx, account_entry:, fund_formula:, capital_commitment:, bdg:, parent:, **)
      # This will setup the amount_cents for the account entry
      # GenerateAccountEntryMultiple passes a per-name substituted formula via
      # ctx[:formula_override]; every other rule type evals the formula as stored.
      formula = ctx[:formula_override] || fund_formula.formula
      eval_formula(ctx, account_entry:, formula:, capital_commitment:, bdg:, parent:, **)
    rescue SkipRule => e
      Rails.logger.debug { "Skipping #{fund_formula.name} for #{capital_commitment}: #{e.message}" }
      # In a real scenario, you might handle this differently
      @skip_rule = true
      true
    end

    # This will set the variable inside the binding for the current_value computed above
    def add_account_entry_value_to_binding(_ctx, account_entry:, bdg:, **)
      # This is so that the variable can be used in YTD, Quarterly, etc. See below
      bdg.local_variable_set(@variable_name.to_sym, account_entry.amount_cents)
    end

    # Note the account_entry may be the original or the one used to generate quarterly, ytd, etc.
    # Note the formula may be the original or the one used to generate quarterly, ytd, etc.
    def eval_formula(ctx, account_entry:, formula:, capital_commitment:, bdg:, parent:, **)
      commitment_cache = ctx[:commitment_cache]
      fund_formula   = ctx[:fund_formula]
      explain        = ctx[:explain]
      bulk_records   = ctx[:bulk_insert_records] || []

      # This skips the with_custom_fields before_save callback, which is used to compute custom fields
      account_entry.skip_cf_before_save = true
      account_entry.form_type_id = ctx[:form_type_id]
      account_entry.capital_commitment_id = capital_commitment&.id
      account_entry.commitment_name = capital_commitment.to_s[0..254] if capital_commitment
      account_entry.folio_id = capital_commitment&.folio_id
      account_entry.fund_id = ctx[:fund].id
      account_entry.generated = true
      account_entry.fund_formula_id = fund_formula.id
      account_entry.allocation_run_id = ctx[:allocation_run_id]

      # Hand the save callbacks below the records we already hold, so they do not load them again
      # per entry: setup_defaults reads capital_commitment, set_folio_amount reads fund,
      # setup_rule_for reads fund_formula. Only the association caches change, never a column.
      preload_associations(account_entry, capital_commitment:, fund_formula:)

      if account_entry.parent_id.nil? && account_entry.parent_id != parent&.id && parent.present?
        account_entry.parent_id = parent.id
        account_entry.parent_type = parent.class.name
        account_entry.parent_name = parent.to_s[0..254] if account_entry.parent_name.blank?
      end

      # Evaluate the formula, but not for Percentage rules, as thats precomputed See ComputeCustomPercentage
      unless fund_formula.rule_type == "Percentage"
        explained = explain && fund_formula.explain
        # The explanation re-evaluates the formula's sub-expressions, re-running the SELECTs the
        # formula just ran for this entry. With the scratch connection's query cache on for this one
        # entry they are answered from memory — same SQL, same unchanged scratch DB, same result.
        with_scratch_query_cache(enabled: explained) do
          account_entry.amount_cents = safe_eval(formula, bdg)
          # Explanation data
          account_entry.explanation = []
          account_entry.explanation << formula
          account_entry.explanation << fund_formula.description if fund_formula.description.present?
          account_entry.explanation << fund_formula.parse_statement(bdg, external_formula: formula).to_json if explained
        end
      end

      # Validate and simulate save
      # account_entry.validate!
      account_entry.setup_defaults
      account_entry.run_callbacks(:save)

      ae_attributes = account_entry.attributes.except("id", "created_at", "updated_at", "generated_deleted")
      ae_attributes[:created_at] = Time.zone.now
      ae_attributes[:updated_at] = Time.zone.now
      bulk_records << ae_attributes

      commitment_cache.add_to_computed_fields_cache(ctx, capital_commitment, account_entry) if capital_commitment
      # ctx[:instance_variables][@variable_name] = account_entry.amount_cents

      ctx[:bulk_insert_records] = bulk_records
    end

    # Seeds the belongs_to caches of a new entry with records the run already has in memory.
    # Each is set only when it is exactly the record the foreign key points at, so a lookup
    # through the association returns what it would have loaded.
    def preload_associations(account_entry, capital_commitment:, fund_formula:)
      # The commitment being allocated to (entries of AccountEntrySqlite point at CapitalCommitmentSqlite)
      if capital_commitment && account_entry.capital_commitment_id == capital_commitment.id &&
         account_entry.association(:capital_commitment).klass == capital_commitment.class
        account_entry.association(:capital_commitment).target = capital_commitment
      end

      # The fund: commitments are loaded with includes(:fund), so the commitment already holds it
      commitment_fund = capital_commitment&.association(:fund)&.target
      if commitment_fund && account_entry.fund_id == commitment_fund.id &&
         account_entry.association(:fund).klass == commitment_fund.class
        account_entry.association(:fund).target = commitment_fund
      end

      # The formula being run
      account_entry.association(:fund_formula).target = fund_formula if fund_formula && account_entry.fund_formula_id == fund_formula.id
    end

    def create_quarterly_account_entry(ctx, fund_formula:, account_entry:, capital_commitment:, bdg:, parent:, **)
      # This is a placeholder for a quarterly account entry
      if fund_formula.generate_ytd_qtly && !@skip_rule

        Rails.logger.debug { "Fund Formula: #{fund_formula.name}, Account Entry: #{account_entry.name}" }

        ae = account_entry.dup
        ae.skip_cf_before_save = true
        ae.name = "Quarterly #{ae.name}"
        # Since this is a rollup, we set the rule_for to reporting
        ae.rule_for = "reporting"
        # Add the formula for the quarterly account entry
        formula = "capital_commitment.quarterly('#{fund_formula.name}', nil, @start_date, @end_date) + #{@variable_name}"
        eval_formula(ctx, account_entry: ae, formula:, capital_commitment:, bdg:, parent:, **)
      else
        true
      end
    end

    def create_ytd_account_entry(ctx, fund_formula:, account_entry:, capital_commitment:, bdg:, parent:, **)
      # This is a placeholder for a year-to-date account entry
      if fund_formula.generate_ytd_qtly && !@skip_rule
        ae = account_entry.dup
        ae.skip_cf_before_save = true
        ae.name = "YTD #{ae.name}"
        # Since this is a rollup, we set the rule_for to reporting
        ae.rule_for = "reporting"
        # Add the formula for the year-to-date account entry
        formula = "capital_commitment.year_to_date('#{fund_formula.name}', nil, @start_date, @end_date) + #{@variable_name}"
        eval_formula(ctx, account_entry: ae, formula:, capital_commitment:, bdg:, parent:, **)
      else
        true
      end
    end

    def create_since_inception_account_entry(ctx, fund_formula:, account_entry:, capital_commitment:, bdg:, parent:, **)
      # This is a placeholder for a since inception account entry
      if fund_formula.generate_ytd_qtly && !@skip_rule
        ae = account_entry.dup
        ae.skip_cf_before_save = true
        ae.name = "Since Inception #{ae.name}"
        # Since this is a rollup, we set the rule_for to reporting
        ae.rule_for = "reporting"
        # add the formula for the since inception account entry
        formula = "capital_commitment.since_inception('#{fund_formula.name}', nil, @start_date, @end_date) + #{@variable_name}"
        eval_formula(ctx, account_entry: ae, formula:, capital_commitment:, bdg:, parent:, **)
      else
        true
      end
    end
  end
end
