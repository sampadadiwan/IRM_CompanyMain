class AccountEntryAllocationEngine
  attr_accessor :cached_generated_fields

  def initialize(fund, start_date, end_date, user_id: nil, rule_for: nil, run_allocations: true, explain: false,
                 generate_soa: false, template_name: nil, fund_ratios: false, sample: false)
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id
    @run_allocations = run_allocations
    @explain = explain
    @generate_soa = generate_soa
    @template_name = template_name
    @fund_ratios = fund_ratios
    @sample = sample
    @rule_for = rule_for
    @helper = AccountEntryAllocationHelper.new(self, fund, start_date, end_date, user_id:)
    @bulk_insert_records = []
  end

  # There are 3 types of formulas - we need to run them in the sequence defined
  def run_formulas
    if @run_allocations
      run_start_time = Time.zone.now
      # Clear all the previous allocations
      @helper.cleaup_prev_allocation(rule_for: @rule_for)
      # Get the fund unit settings mapped by name
      fund_unit_settings = FundUnitSetting.where(fund_id: @fund.id).index_by(&:name)
      # Pick only the enabled formulas
      formulas = FundFormula.enabled.where(fund_id: @fund.id).order(sequence: :asc)
      formulas = formulas.where(rule_for: @rule_for) if @rule_for.present?
      @formula_count = formulas.count

      formulas.each_with_index do |fund_formula, index|
        @formula_index = index
        # Run the formula, but time it
        start_time = Time.zone.now
        run_formula(fund_formula, fund_unit_settings)

        # Store the time taken to run the formula
        fund_formula.update_column(:execution_time, ((Time.zone.now - start_time) * 1000).to_i)

        # Provide notification
        @helper.notify("Completed #{index + 1} of #{@formula_count}: #{fund_formula.name}", :success, @user_id)
      rescue Exception => e
        @helper.notify("Error in Formula #{fund_formula.sequence}: #{fund_formula.name} : #{e.message}", :danger, @user_id)
        Rails.logger.debug { "Error in #{fund_formula.name} : #{e.message}" }
        raise e
      end
      time_taken = ((Time.zone.now - run_start_time)).to_i
      @helper.notify("Done running all allocations for #{@start_date} - #{@end_date} in #{time_taken} seconds", :success, @user_id)
    end

    @helper.generate_fund_ratios if @fund_ratios
    @helper.generate_soa(@template_name) if @generate_soa
  end

  def run_formula(fund_formula, fund_unit_settings)
    @bulk_insert_records = []
    existing_record_count = @fund.account_entries.generated.count
    puts { "Running formula #{fund_formula.name}" }

    # Rollups are based on the name and entry_type, except for portfolio investments
    rollup_name = fund_formula.name
    rollup_entry_type = fund_formula.entry_type

    case fund_formula.rule_type
    when "GenerateCustomField"
      generate_custom_fields(fund_formula, fund_unit_settings)
    when "AllocateAccountEntry", "AllocateAccountEntry-Name"
      allocate_account_entries(fund_formula, fund_unit_settings, "name")
    when "AllocateAccountEntry-EntryType"
      allocate_account_entries(fund_formula, fund_unit_settings, "entry_type")
    when "CumulateAccountEntry"
      cumulate_account_entries(fund_formula, fund_unit_settings)
    when "GenerateAccountEntry"
      generate_account_entries(fund_formula, fund_unit_settings)
    when "AllocatePortfolio"
      allocate_aggregate_portfolios(fund_formula, fund_unit_settings)
    when "AllocatePortfolioInvestment"
      allocate_portfolios_investment(fund_formula, fund_unit_settings)
      # portfolio investments rollups is based on the entry type and not the name
      rollup_name = nil
      rollup_entry_type = fund_formula.name
    when "Percentage"
      compute_custom_percentage(fund_formula)
    end

    # At this point eh formulas are run, and we have the account_entries in @bulk_insert_records
    # Insert the records in bulk
    bulk_insert_data(fund_formula, fund_unit_settings, existing_record_count, rollup_name, rollup_entry_type)
  end

  def bulk_insert_data(fund_formula, fund_unit_settings, existing_record_count, rollup_name, rollup_entry_type)
    if @bulk_insert_records.present?
      result = AccountEntry.insert_all(@bulk_insert_records)
      total_record_count = @fund.account_entries.generated.reload.count
      inserted_rown_count = total_record_count - existing_record_count
      Rails.logger.debug { "#{fund_formula.name}: Inserted #{inserted_rown_count} of #{@bulk_insert_records.length} records, total: #{total_record_count}" }
      raise "Inserts failed" if inserted_rown_count != @bulk_insert_records.length
    else
      Rails.logger.debug { "#{fund_formula.name}: No records to insert" }
    end

    # Rollup the account entries
    if fund_formula.roll_up
      @bulk_insert_records = []
      fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, _idx|
        cumulative_ae = capital_commitment.rollup_account_entries(rollup_name, rollup_entry_type, @start_date, @end_date)
        @bulk_insert_records << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
        @helper.add_to_computed_fields_cache(capital_commitment, cumulative_ae)
      end
      result = AccountEntry.insert_all(@bulk_insert_records) if @bulk_insert_records.present?
      rollup_inserted_rown_count = @fund.account_entries.generated.reload.count - inserted_rown_count
      Rails.logger.debug { "#{fund_formula.name}: Inserted #{rollup_inserted_rown_count} roll_up records" }
      raise "Rollup inserts failed" if rollup_inserted_rown_count != @bulk_insert_records.length
    else
      Rails.logger.debug { "#{fund_formula.name}: No roll_up records to insert" }
    end

    # This is special treatment for GenerateAccountEntry
    if fund_formula.rule_type == "GenerateAccountEntry"
      @bulk_insert_records = []
      rollup_as_fund_account_entry(fund_formula, fund_unit_settings)
    end
  end

  # This in theory generates a custom field variable that can be used in other formulas
  # Its never saved to the DB
  def generate_custom_fields(fund_formula, fund_unit_settings)
    Rails.logger.debug { "generate_custom_fields #{fund_formula.name}" }
    # Generate the cols required
    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, idx|
      Rails.logger.debug { "Generating using formula #{fund_formula} for #{capital_commitment}, #{@start_date}, #{@end_date}" }

      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]
      Rails.logger.debug { "No fund_unit_setting found for #{capital_commitment.to_json}" } unless fund_unit_setting

      ae = AccountEntry.new(name: fund_formula.name, fund_formula:,
                            amount_cents: @helper.safe_eval(fund_formula.formula, binding))
      @helper.add_to_computed_fields_cache(capital_commitment, ae)

      # This is used to generate instance variables from the cached computed values
      fields = @helper.computed_fields_cache(capital_commitment, @start_date)

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  def compute_custom_percentage(fund_formula)
    field_name = fund_formula.formula
    total = 0
    count = 0
    cc_map = {}

    # Loop thru all the commitments and get the total of the account entry "field_name"
    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, _idx|
      # Get the last entry for the field_name before the end date
      amount_cents = capital_commitment.account_entries.where(name: field_name, reporting_date: ..@end_date).order(reporting_date: :asc).last.amount_cents

      cc_map[capital_commitment.id] = {}
      cc_map[capital_commitment.id]["amount_cents"] = amount_cents
      cc_map[capital_commitment.id]["entry_type"] = "Percentage"

      total += amount_cents
      count += 1
    end

    # Delete all prev generated percentage
    AccountEntry.where(name: "#{field_name} Percentage", entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, generated: true).find_each(&:destroy)

    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, idx|
      percentage = total.positive? ? (100.0 * cc_map[capital_commitment.id]["amount_cents"] / total) : 0

      ae = AccountEntry.new(name: "#{field_name} Percentage", entry_type: cc_map[capital_commitment.id]["entry_type"], entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", capital_commitment:, folio_id: capital_commitment.folio_id, generated: true, amount_cents: percentage, cumulative: false, fund_formula:, commitment_type: fund_formula.commitment_type)

      ae.validate!
      ae.run_callbacks(:save)
      ae_attributes = ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
      ae_attributes[:created_at] = Time.zone.now
      ae_attributes[:updated_at] = Time.zone.now
      @bulk_insert_records << ae_attributes

      @helper.add_to_computed_fields_cache(capital_commitment, ae)

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  # Used to allocate the portfolio FMV and costs based on a formula
  # E.x capital_commitment.percentage * aggregate_portfolio_investments.fmv_cents / 100
  def allocate_aggregate_portfolios(fund_formula, fund_unit_settings)
    Rails.logger.debug { "allocate_aggregate_portfolios(#{fund_formula.name}, #{fund_unit_settings})" }

    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, idx|
      # This is used to generate instance variables from the cached computed values
      fields = @helper.computed_fields_cache(capital_commitment, @start_date)
      apis = capital_commitment.Pool? ? @fund.aggregate_portfolio_investments.pool : []
      # Only pool APIs should be used to generate account_entries
      apis.each do |orig_api|
        ae = AccountEntry.new(name: "#{orig_api.portfolio_company_name}-#{orig_api.investment_type}", entry_type: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", generated: true, fund_formula:)

        # This will create the AggregatePortfolioInvestment as of the end date, it will be used in the formulas
        api = orig_api.as_of(nil, @end_date)
        api_period = orig_api.as_of @start_date, @end_date
        begin
          ae = create_account_entry(ae, fund_formula, capital_commitment, orig_api, binding)
        rescue Exception => e
          raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
        end
      end

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  def allocate_portfolios_investment(fund_formula, fund_unit_settings)
    Rails.logger.debug { "allocate_aggregate_portfolios(#{fund_formula.name}, #{fund_unit_settings})" }
    # We use the pool PIs as only pool PIs are allocated, Co Invest is specific to a commitment
    portfolio_investments = @fund.portfolio_investments.pool.where(investment_date: ..@end_date)

    fund_formula.commitments(@end_date, @sample).pool.each_with_index do |capital_commitment, idx|
      # This is used to generate instance variables from the cached computed values
      fields = @helper.computed_fields_cache(capital_commitment, @start_date)

      portfolio_investments.each do |portfolio_investment|
        ae = AccountEntry.new(name: portfolio_investment.to_s, entry_type: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", generated: true, fund_formula:)

        begin
          ae = create_account_entry(ae, fund_formula, capital_commitment, portfolio_investment, binding)
        rescue Exception => e
          raise "Error in #{fund_formula.name} for #{capital_commitment} #{portfolio_investment}: #{e.message}"
        end
      end

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  def create_account_entry(account_entry, fund_formula, capital_commitment, parent, bdg, save_now: false)
    begin
      account_entry.capital_commitment = capital_commitment
      account_entry.folio_id = capital_commitment.folio_id
      account_entry.amount_cents = @helper.safe_eval(fund_formula.formula, bdg)

      account_entry.explanation = []
      account_entry.explanation << fund_formula.formula
      account_entry.explanation << fund_formula.description
      account_entry.explanation << fund_formula.parse_statement(bdg).to_json if @explain

      account_entry.parent = parent
      account_entry.generated = true
      account_entry.commitment_type = fund_formula.commitment_type
      account_entry.fund_formula = fund_formula

      if save_now
        # Save the account entry
        account_entry.save!
      else
        # Validate the account entry
        account_entry.validate!
        account_entry.run_callbacks(:save)
        # Add the account entry to the bulk insert records
        ae_attributes = account_entry.attributes.except("id", "created_at", "updated_at", "generated_deleted")
        ae_attributes[:created_at] = Time.zone.now
        ae_attributes[:updated_at] = Time.zone.now
        @bulk_insert_records << ae_attributes
      end

      @helper.add_to_computed_fields_cache(capital_commitment, account_entry)
    rescue SkipRule => e
      Rails.logger.debug { "Skipping #{fund_formula.name} for #{capital_commitment}: #{e.message}" }
    end
    account_entry
  end

  # Generate account entries of the fund, to the various capital commitments in the fund based on formulas
  # This is different from allocate_account_entries, in that it does not need a fund account entry to allocate
  # E.x fund_unit_setting.management_fee * 100 * capital_commitment.percentage / 100.0
  def generate_account_entries(fund_formula, fund_unit_settings)
    Rails.logger.debug { "generate_account_entries(#{fund_formula.name}, #{fund_formula.formula}, #{fund_unit_settings})" }

    cumulative = !fund_formula.roll_up

    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, idx|
      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

      # This is used to generate instance variables from the cached computed values
      fields = @helper.computed_fields_cache(capital_commitment, @start_date)

      ae = AccountEntry.new(name: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", entry_type: fund_formula.entry_type, generated: true, cumulative: false, fund_formula:)

      begin
        create_account_entry(ae, fund_formula, capital_commitment, nil, binding)
      rescue Exception => e
        raise "Error in #{fund_formula.name} for #{capital_commitment}: #{e.message}"
      end

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  # For those account entries that are generated, we also roll them up at the fund level.
  # This is a historical thing, its a special treatment for generate_account_entries
  def rollup_as_fund_account_entry(fund_formula, _fund_unit_settings)
    # Generate fund account entry
    @fund.fund_account_entries.where(name: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, entry_type: fund_formula.entry_type, generated: true, capital_commitment_id: nil).find_each(&:destroy)

    account_entries = @fund.account_entries.where(name: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, entry_type: fund_formula.entry_type, generated: true, cumulative: false)

    account_entries = account_entries.where(reporting_date: ..@end_date)
    account_entries = account_entries.where(reporting_date: @start_date..)

    @fund.fund_account_entries.create(name: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, entry_type: fund_formula.entry_type, generated: true, cumulative: true, commitment_type: fund_formula.commitment_type, amount_cents: account_entries.sum(:amount_cents))
  end

  # Used to generate cumulative account entries for things such as TDS which is uploaded by the fund per commitment
  def cumulate_account_entries(fund_formula, _fund_unit_settings)
    @bulk_insert_records = []
    fund_formula.commitments(@end_date, @sample).each do |capital_commitment|
      Rails.logger.debug { "Cumulating #{fund_formula} to #{capital_commitment}" }

      next unless fund_formula.roll_up

      # Rollup this allocation for each commitment
      cumulative_ae = capital_commitment.rollup_account_entries(fund_formula.name, fund_formula.entry_type, @start_date, @end_date)
      @bulk_insert_records << cumulative_ae.attributes.except("id", "created_at", "updated_at", "generated_deleted")
      @helper.add_to_computed_fields_cache(capital_commitment, cumulative_ae)
    end

    count = AccountEntry.insert_all(@bulk_insert_records) if @bulk_insert_records.present?
    Rails.logger.debug { "#{fund_formula.name}: Inserted #{count} roll_up records" }
  end

  # ALlocate account entries of the fund, to the varios capital commitments in the fund based on formulas
  # E.x fund_account_entry.amount_cents * capital_commitment.properties['opening_investable_capital_percentage'] / 100.0
  def allocate_account_entries(fund_formula, fund_unit_settings, name_or_entry_type = "name")
    Rails.logger.debug { "allocate_account_entries  #{fund_formula.name}" }
    # Compute the allocation

    account_entries = @fund.fund_account_entries.where(reporting_date: @start_date..).where(reporting_date: ..@end_date).where(commitment_type: fund_formula.commitment_type)

    account_entries = name_or_entry_type == "name" ? account_entries.where(name: fund_formula.name) : account_entries.where(entry_type: fund_formula.name)

    if account_entries.present?
      # Each account entry with the formula name, has to be allocated
      account_entries.each do |fund_account_entry|
        Rails.logger.debug { "allocate_account_entries  #{fund_formula.name}: Allocating #{fund_account_entry}" }
        allocate_entry(fund_account_entry, fund_formula, fund_unit_settings)
      end
    else
      Rails.logger.warn "No account entries found to allocate for #{fund_formula.name} in #{@fund.name}"
    end
  end

  def allocate_entry(fund_account_entry, fund_formula, fund_unit_settings)
    fund_formula.commitments(@end_date, @sample).each_with_index do |capital_commitment, idx|
      Rails.logger.debug { "Allocating #{fund_account_entry} to #{capital_commitment}" }

      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

      # This is used to generate instance variables from the cached computed values
      fields = @helper.computed_fields_cache(capital_commitment, @start_date)

      # Allocate this fund_account_entry to this capital_commitment
      ae = fund_account_entry.dup

      begin
        create_account_entry(ae, fund_formula, capital_commitment, fund_account_entry, binding)
      rescue Exception => e
        raise "Error in #{fund_formula.name} for #{capital_commitment} #{fund_account_entry}: #{e.message}"
      end

      @helper.notify("Completed #{@formula_index + 1} of #{@formula_count}: #{fund_formula.name} : #{idx + 1} commitments", :success, @user_id) if ((idx + 1) % 10).zero?
    end
  end

  def create_variables(cached_commitment_fields)
    # Create variables available to eval here from all the cached fields
    # This is what allows formulas to have things line @cash_in_hand or @units
    cached_commitment_fields.keys.sort.each do |f|
      # variable names cannot be created with special chars - so delete them
      variable_name = f.delete('.&:')
      # Use meta programming to setup an instance variable
      instance_variable_set(:"@#{variable_name}", cached_commitment_fields[f])
      Rails.logger.debug { "Setting up variable @#{variable_name} to #{cached_commitment_fields[f]}" }
    end
  end
end
