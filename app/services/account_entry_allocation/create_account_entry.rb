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
      formula = fund_formula.formula
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

      account_entry.capital_commitment = capital_commitment
      account_entry.folio_id = capital_commitment&.folio_id

      account_entry.parent          = parent
      account_entry.generated       = true
      account_entry.fund_formula    = fund_formula
      account_entry.allocation_run_id = ctx[:allocation_run_id]

      account_entry.amount_cents = safe_eval(formula, bdg)
      # Explanation data
      account_entry.explanation = []
      account_entry.explanation << formula
      account_entry.explanation << fund_formula.description
      account_entry.explanation << fund_formula.parse_statement(bdg, external_formula: formula).to_json if explain && fund_formula.explain

      # Validate and simulate save
      account_entry.validate!
      account_entry.run_callbacks(:save)

      ae_attributes = account_entry.attributes.except("id", "created_at", "updated_at", "generated_deleted")
      ae_attributes[:created_at] = Time.zone.now
      ae_attributes[:updated_at] = Time.zone.now
      bulk_records << ae_attributes

      commitment_cache.add_to_computed_fields_cache(capital_commitment, account_entry) if capital_commitment
      # ctx[:instance_variables][@variable_name] = account_entry.amount_cents

      ctx[:bulk_insert_records] = bulk_records
    end

    def create_quarterly_account_entry(ctx, fund_formula:, account_entry:, capital_commitment:, bdg:, parent:, **)
      # This is a placeholder for a quarterly account entry
      if fund_formula.generate_ytd_qtly && !@skip_rule
        ae = account_entry.dup
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
