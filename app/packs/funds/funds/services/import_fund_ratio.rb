class ImportFundRatio < ImportUtil
  # All columns the spreadsheet must contain; extra columns become custom fields
  STANDARD_HEADERS = ["Fund", "Folio No", "Portfolio Company", "Instrument", "Ratio Name", "Value", "End Date", "Label", "Note", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @fund_ratios = []
    # Tracks unique (fund, end_date) pairs processed during the import so we can
    # refresh the latest flag once all rows are saved, rather than per row.
    @fund_end_dates = Set.new
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing Fund Ratio #{user_data}" }

    fund   = find_fund(import_upload, user_data["Fund"])
    entity = import_upload.entity
    # Owner determines what the ratio is attached to: fund, investor, instrument, or commitment
    owner  = find_owner(fund, user_data, entity)

    # Portfolio scenario is optional; when present the ratio is set as computation_context.
    portfolio_scenario_name = user_data["Portfolio Scenario"]&.strip
    portfolio_scenario      = portfolio_scenario_name.present? ?
                                fund.portfolio_scenarios.find_by(name: portfolio_scenario_name) : nil
    raise "Portfolio Scenario not found for #{portfolio_scenario_name}" if portfolio_scenario_name.present? && portfolio_scenario.nil?

    # Scenario defaults to "Default" when the column is blank
    scenario = user_data["Scenario"]&.strip || "Default"
    # end_date is the period-end this ratio represents; nil means open-ended
    end_date = user_data["End Date"].present? ? parse_date(user_data["End Date"]) : nil

    attributes = {
      fund:           fund,
      entity:         entity,
      owner:          owner,
      user_data:      user_data,
      value:          parse_value(user_data["Value"]),
      display_value:  format_display_value(user_data["Value"], user_data["Ratio Name"]),
      end_date:       end_date,
      import_upload:  import_upload,
      scenario:       scenario
    }
    # Set computation_context to the PortfolioScenario when one was resolved.
    # scenario string is also set explicitly here because the before_create callback
    # only fires on blank scenario — imports may override with a custom value.
    attributes[:computation_context] = portfolio_scenario if portfolio_scenario

    # "Update Only = yes" means the ratio must already exist; error out if it doesn't
    if user_data["Update Only"].to_s.downcase == "yes"
      update_fund_ratio(attributes)
    else
      create_fund_ratio(attributes)
    end

    # Record the (fund, end_date) pair so post_process can recalculate the latest flag
    @fund_end_dates << [fund, end_date]
  end

  # After all rows are saved, recalculate which ratio is "latest" per fund+scenario.
  # Done once here rather than per-row to avoid redundant updates mid-import.
  def post_process(ctx, import_upload:, **)
    result = super # runs counter-culture deferred updates if applicable
    # Skip nil end_dates — open-ended ratios have no date ordering to resolve,
    # and update_latest would raise when comparing nil with <=.
    @fund_end_dates.each { |fund, end_date| fund.update_latest_fund_ratios(end_date) if end_date.present? }
    result
  end

  private

  # Looks up the fund by name, scoped to the entity that owns the import
  def find_fund(import_upload, fund_name)
    fund = import_upload.entity.funds.where(name: fund_name).last
    raise "Fund not found for #{fund_name}" if fund.nil?

    fund
  end

  # Determines the polymorphic owner of the fund ratio based on which columns are populated:
  #   Folio No present                        → CapitalCommitment
  #   Portfolio Company + Instrument present  → AggregatePortfolioInvestment
  #   Portfolio Company only                  → PortfolioCompany (Investor)
  #   None of the above                       → Fund
  # Investor-level ratios are intentionally unsupported pending product clarity.
  def find_owner(fund, user_data, entity)
    # Folio No and Portfolio Company/Instrument are mutually exclusive lookup paths
    raise "Invalid Owner: If 'Folio No' is present, 'Portfolio Company' and 'Instrument' must be blank." if user_data["Folio No"].present? && (user_data["Portfolio Company"].present? || user_data["Instrument"].present?)

    if user_data["Folio No"].present?
      # Capital commitment identified by the folio number stamped on the commitment
      fund.capital_commitments.find_by(folio_id: user_data["Folio No"]).tap do |capital_commitment|
        raise "Capital Commitment not found for #{user_data['Folio No']}" if capital_commitment.nil?
      end
    elsif user_data["Portfolio Company"].present?
      investor = entity.investors.find_by(investor_name: user_data["Portfolio Company"])
      raise "Portfolio Company not found for #{user_data['Portfolio Company']}" if investor.nil?

      if user_data["Instrument"].present?
        # Instrument narrows the owner down to the specific AggregatePortfolioInvestment
        instrument = investor.investment_instruments.find_by(name: user_data["Instrument"])
        raise "Instrument #{user_data['Instrument']} not found for #{user_data['Portfolio Company']}" if instrument.nil?

        # The API must exist for this fund to be a valid target
        api = instrument.aggregate_portfolio_investment.find_by(fund_id: fund.id)
        raise "Aggregate Portfolio Investment not found for instrument #{user_data['Instrument']} and fund #{fund.name}" if api.nil?

        api
      else
        # Portfolio Company without an instrument → ratio belongs to the investor directly
        investor
      end
    else
      # No granular owner specified; ratio belongs to the fund itself
      fund
    end
  end

  # Store as BigDecimal for precision; display value is formatted separately
  def parse_value(value)
    value.to_d
  end

  # IRR-style ratios display as percentage; everything else is a multiplier (e.g. 2.5 x)
  def format_display_value(value, ratio_name)
    formatted_value = value.to_d.to_f.round(2)

    if ["XIRR", "Fund Utilization", "Gross Portfolio IRR"].include?(ratio_name) || ratio_name.include?("IRR")
      "#{formatted_value} %"
    else
      "#{formatted_value} x"
    end
  end

  # Uses Date.local_parse so timezone-aware parsing matches the app's locale setting
  def parse_date(date_string)
    Date.local_parse(date_string)
  rescue ArgumentError
    raise "Invalid date format for #{date_string}"
  end

  # Finds an existing FundRatio by identity (fund + entity + owner + name) and overwrites its values.
  # Does NOT guard against duplicate end_dates — "Update Only" rows are expected to already exist.
  def update_fund_ratio(attrs)
    fund_ratio = FundRatio.find_by(
      fund_id: attrs[:fund].id,
      entity_id: attrs[:entity].id,
      owner_type: attrs[:owner].class.name,
      owner_id: attrs[:owner].id,
      name: attrs[:user_data]["Ratio Name"]
    )

    raise "Fund Ratio not found for update: #{attrs[:user_data]}" if fund_ratio.nil?

    fund_ratio.assign_attributes(
      value:               attrs[:value],
      display_value:       attrs[:display_value],
      end_date:            attrs[:end_date],
      import_upload_id:    attrs[:import_upload].id,
      notes:               attrs[:user_data]["Note"],
      label:               attrs[:user_data]["Label"],
      scenario:            attrs[:scenario],
      computation_context: attrs[:computation_context]
    )
    fund_ratio.save!
  end

  # Creates a new FundRatio, rejecting duplicates on the same (fund, entity, name, owner, end_date) key.
  # capital_commitment_id is a denormalised FK kept in sync with owner when owner is a CapitalCommitment.
  def create_fund_ratio(attrs)
    # Uniqueness is enforced at the application layer; (name, end_date, owner) must be unique per fund
    existing_fund_ratio = FundRatio.find_by(
      fund_id:                  attrs[:fund].id,
      entity_id:                attrs[:entity].id,
      name:                     attrs[:user_data]["Ratio Name"],
      computation_context_type: attrs[:computation_context]&.class&.name,
      computation_context_id:   attrs[:computation_context]&.id,
      owner_type:               attrs[:owner].class.name,
      owner_id:                 attrs[:owner].id,
      end_date:                 attrs[:end_date]
    )

    raise "Fund Ratio already exists for the given period (end date: #{attrs[:end_date]})" if existing_fund_ratio

    fund_ratio = FundRatio.new(
      fund_id:             attrs[:fund].id,
      entity_id:           attrs[:entity].id,
      owner_type:          attrs[:owner].class.name,
      owner_id:            attrs[:owner].id,
      name:                attrs[:user_data]["Ratio Name"],
      value:               attrs[:value],
      display_value:       attrs[:display_value],
      end_date:            attrs[:end_date],
      import_upload_id:    attrs[:import_upload].id,
      notes:               attrs[:user_data]["Note"],
      label:               attrs[:user_data]["Label"],
      scenario:            attrs[:scenario],
      computation_context: attrs[:computation_context]
    )

    # Denormalised column — only set when the ratio is scoped to a specific commitment
    fund_ratio.capital_commitment_id = attrs[:owner].id if attrs[:owner].is_a?(CapitalCommitment)
    fund_ratio.save!
  end
end
