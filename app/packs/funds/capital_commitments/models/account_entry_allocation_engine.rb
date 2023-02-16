class AccountEntryAllocationEngine
  # This is to split the formula and retain the delimiters
  # See https://stackoverflow.com/questions/18089562/how-do-i-keep-the-delimiters-when-splitting-a-ruby-string
  FORMULA_DELIMS = %r{([?+|\-*/()%=]):} # ["+","-","*","/","(",")","%", "="]

  def initialize(fund, start_date, end_date, formula_id: nil, user_id: nil, generate_soa: false)
    @fund = fund
    @start_date = start_date
    @end_date = end_date
    @formula_id = formula_id
    @user_id = user_id
    @generate_soa = generate_soa
  end

  # There are 3 types of formulas - we need to run them in the sequence defined
  def run_formulas
    cleaup_prev_allocation

    fund_unit_settings = FundUnitSetting.where(fund_id: @fund.id).index_by(&:name)

    formulas = FundFormula.enabled.where(fund_id: @fund.id).order(sequence: :asc)
    if @formula_id.present?
      formulas = formulas.where(id: @formula_id)
      Rails.logger.debug { "##### Running only formula #{formulas}" }
    end

    count = formulas.count

    formulas.each_with_index do |fund_formula, index|
      Rails.logger.debug { "Running formula #{fund_formula.name}" }

      case fund_formula.rule_type
      when "GenerateCustomField"
        generate_custom_fields(fund_formula, fund_unit_settings)
      when "AllocateAccountEntry"
        allocate_account_entries(fund_formula, fund_unit_settings)
      when "CumulateAccountEntry"
        cumulate_account_entries(fund_formula, fund_unit_settings)
      when "GenerateAccountEntry"
        generate_account_entries(fund_formula, fund_unit_settings)
      when "AllocatePortfolio"
        allocate_portfolio_investments(fund_formula, fund_unit_settings)
      when "Percentage"
        compute_custom_percentage(fund_formula.formula)
      end

      notify("Completed #{index + 1} of #{count}: #{fund_formula.name}", :success, @user_id)
    end

    notify("Done running all allocations for #{@start_date} - #{@end_date}", :success, @user_id)

    generate_soa if @generate_soa
  end

  def generate_soa
    @fund.capital_commitments.each do |capital_commitment|
      CapitalCommitmentSoaJob.perform_now(capital_commitment.id, @start_date, @end_date, @user_id)
    end
  end

  def cleaup_prev_allocation
    # Remove all prev allocations for this period, as we will recompute it
    AccountEntry.where(fund_id: @fund.id, generated: true, reporting_date: @start_date..).where(reporting_date: ..@end_date).where.not(capital_commitment_id: nil).delete_all
    notify("Cleaned up prev allocated entries", :success, @user_id)
  end

  # This in theory generates a custom field in the commitment
  # E.x capital_commitment["properties"]["opening_investable_capital"] = capital_commitment.collected_amount_cents + capital_commitment.account_entries.total_amount('Income', end_date: @start_date) - capital_commitment.account_entries.total_amount('Expense', end_date: @start_date)
  def generate_custom_fields(fund_formula, fund_unit_settings)
    Rails.logger.debug { "generate_custom_fields #{fund_formula.name}" }
    # Generate the cols required
    @fund.capital_commitments.each do |capital_commitment|
      Rails.logger.debug { "Generating using #{fund_formula} for #{capital_commitment}, #{@start_date}, #{@end_date}" }

      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]
      Rails.logger.debug { "No fund_unit_setting found for #{capital_commitment.to_json}" } unless fund_unit_setting

      begin
        printable = ""
        fund_formula.formula.split(FORMULA_DELIMS).each do |token|
          pt = token.length > 1 ? eval(token).to_s : token.to_s
          printable += " #{pt}"
        end
      rescue StandardError => e
        Rails.logger.debug e.message
      end

      Rails.logger.debug printable

      eval(fund_formula.formula)
      capital_commitment.save
    end
  end

  def compute_custom_percentage(field_name)
    total = 0
    count = 0

    @fund.capital_commitments.each do |capital_commitment|
      total += capital_commitment.properties[field_name]
      count += 1
    end

    @fund.capital_commitments.each do |capital_commitment|
      percentage = total.positive? ? (100.0 * capital_commitment.properties[field_name.to_s] / total) : 0
      capital_commitment.properties["#{field_name}_percentage"] = percentage.round(4)
      capital_commitment.save
    end
  end

  # Used to allocate the portfolio FMV and costs based on a formula
  # E.x capital_commitment.percentage * aggregate_portfolio_investments.fmv_cents / 100
  def allocate_portfolio_investments(fund_formula, fund_unit_settings)
    Rails.logger.debug { "allocate_portfolio_investments(#{fund_formula.name}, #{fund_unit_settings})" }

    @fund.capital_commitments.each do |capital_commitment|
      @fund.aggregate_portfolio_investments.each do |api|
        ae = AccountEntry.new(name: api.portfolio_company_name, entry_type: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", generated: true)

        ae.capital_commitment = capital_commitment
        ae.folio_id = capital_commitment.folio_id
        ae.amount_cents = eval(fund_formula.formula)
        ae.explanation = []
        ae.explanation << fund_formula.formula
        ae.explanation << fund_formula.description
        ae.parent = api

        printable = ""
        begin
          fund_formula.formula.split(FORMULA_DELIMS).each do |token|
            pt = token.length > 1 ? eval(token).to_s : token.to_s
            printable += " #{pt}"
          end
          ae.explanation << printable
        rescue StandardError => e
          Rails.logger.error e.message
        end

        ae.save!
      end

      capital_commitment.rollup_account_entries(nil, fund_formula.name, @start_date, @end_date)
    end
  end

  # Generate account entries of the fund, to the various capital commitments in the fund based on formulas
  # This is different from allocate_account_entries, in that it does not need a fund account entry to allocate
  # E.x fund_unit_setting.management_fee * 100 * capital_commitment.percentage / 100.0
  def generate_account_entries(fund_formula, fund_unit_settings)
    Rails.logger.debug { "generate_account_entries(#{fund_formula.name}, #{fund_unit_settings})" }

    @fund.capital_commitments.each do |capital_commitment|
      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

      ae = AccountEntry.new(name: fund_formula.name, entity_id: @fund.entity_id, fund: @fund, reporting_date: @end_date, period: "As of #{@end_date}", entry_type: fund_formula.entry_type, generated: true)

      ae.capital_commitment = capital_commitment
      ae.folio_id = capital_commitment.folio_id
      ae.amount_cents = eval(fund_formula.formula)
      ae.explanation = []
      ae.explanation << fund_formula.formula
      ae.explanation << fund_formula.description

      printable = ""
      begin
        fund_formula.formula.split(FORMULA_DELIMS).each do |token|
          pt = token.length > 1 ? eval(token).to_s : token.to_s
          printable += " #{pt}"
        end
        ae.explanation << printable
      rescue StandardError => e
        Rails.logger.error e.msg
      end

      ae.save!

      # Rollup this allocation for each commitment
      capital_commitment.rollup_account_entries(ae.name, ae.entry_type, @start_date, @end_date)
    end
  end

  # Used to generate cumulative account entries for things such as TDS which is uploaded by the fund per commitment
  def cumulate_account_entries(fund_formula, _fund_unit_settings)
    # binding.pry
    @fund.capital_commitments.each do |capital_commitment|
      Rails.logger.debug { "Cumulating #{fund_formula} to #{capital_commitment}" }

      # Rollup this allocation for each commitment
      capital_commitment.rollup_account_entries(fund_formula.name, fund_formula.entry_type, @start_date, @end_date)
    end
  end

  # ALlocate account entries of the fund, to the varios capital commitments in the fund based on formulas
  # E.x fund_account_entry.amount_cents * capital_commitment.properties['opening_investable_capital_percentage'] / 100.0
  def allocate_account_entries(fund_formula, fund_unit_settings)
    Rails.logger.debug { "allocate_account_entries  #{fund_formula.name}" }
    # Compute the allocation
    account_entries = @fund.fund_account_entries.where(reporting_date: @start_date.., name: fund_formula.name).where(reporting_date: ..@end_date)

    account_entries.each do |fund_account_entry|
      allocate_entry(fund_account_entry, fund_formula, fund_unit_settings)
    end
  end

  def allocate_entry(fund_account_entry, fund_formula, fund_unit_settings)
    @fund.capital_commitments.each do |capital_commitment|
      Rails.logger.debug { "Allocating #{fund_account_entry} to #{capital_commitment}" }

      fund_unit_setting = fund_unit_settings[capital_commitment.unit_type]

      # Allocate this fund_account_entry to this capital_commitment
      ae = fund_account_entry.dup
      ae.generated = true
      ae.parent = fund_account_entry
      ae.capital_commitment = capital_commitment
      ae.folio_id = capital_commitment.folio_id
      ae.amount_cents = eval(fund_formula.formula)

      ae.explanation = []
      ae.explanation << fund_formula.formula
      ae.explanation << fund_formula.description
      ae.period = "#{@start_date} - #{@end_date}"

      printable = ""
      begin
        fund_formula.formula.split(FORMULA_DELIMS).each do |token|
          pt = token.length > 1 ? eval(token).to_s : token.to_s
          printable += " #{pt}"
        end
        ae.explanation << printable
      rescue StandardError => e
        Rails.logger.error e.message
      end

      ae.save!

      # Rollup this allocation for each commitment
      capital_commitment.rollup_account_entries(ae.name, ae.entry_type, @start_date, @end_date)
    end
  end

  def notify(message, level, user_id)
    UserAlert.new(user_id:, message:, level:).broadcast if user_id.present?
  end
end
