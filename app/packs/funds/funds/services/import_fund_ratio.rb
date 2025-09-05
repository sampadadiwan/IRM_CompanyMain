class ImportFundRatio < ImportUtil
  STANDARD_HEADERS = ["Fund", "Folio No", "Portfolio Company", "Instrument", "Ratio Name", "Value", "End Date", "Label", "Note", "Update Only"].freeze

  def standard_headers
    STANDARD_HEADERS
  end

  def initialize(**)
    super
    @fund_ratios = []
  end

  def save_row(user_data, import_upload, _custom_field_headers, _ctx)
    Rails.logger.debug { "Processing Fund Ratio #{user_data}" }

    fund = find_fund(user_data["Fund"])
    entity = import_upload.entity
    owner = find_owner(fund, user_data, entity)

    attributes = {
      fund: fund,
      entity: entity,
      owner: owner,
      user_data: user_data,
      value: parse_value(user_data["Value"]),
      display_value: format_display_value(user_data["Value"], user_data["Ratio Name"]),
      end_date: parse_date(user_data["End Date"]),
      import_upload: import_upload
    }

    if user_data["Update Only"].to_s.downcase == "yes"
      update_fund_ratio(attributes)
    else
      create_fund_ratio(attributes)
    end
  end

  private

  def find_fund(fund_name)
    fund = Fund.find_by(name: fund_name)
    raise "Fund not found for #{fund_name}" if fund.nil?

    fund
  end

  # For now. We want to disable investor fund ratios as this is unclear from product perspective.
  def find_owner(fund, user_data, entity)
    # Validate that if "Folio No" is present, "Portfolio Company" and "Instrument" are blank
    raise "Invalid Owner: If 'Folio No' is present, 'Portfolio Company' and 'Instrument' must be blank." if user_data["Folio No"].present? && (user_data["Portfolio Company"].present? || user_data["Instrument"].present?)

    if user_data["Folio No"].present?
      fund.capital_commitments.find_by(folio_id: user_data["Folio No"]).tap do |capital_commitment|
        raise "Capital Commitment not found for #{user_data['Folio No']}" if capital_commitment.nil?
      end
    elsif user_data["Instrument"].present? && user_data["Portfolio Company"].present?
      investor = entity.investors.find_by(investor_name: user_data["Portfolio Company"])
      raise "Portfolio Company not found for #{user_data['Portfolio Company']}" if investor.nil?

      instrument = investor.investment_instruments.find_by(name: user_data["Instrument"])
      raise "Instrument not found for #{user_data['Instrument']}" if instrument.nil?

      instrument.aggregate_portfolio_investment.find_by(fund_id: fund.id)
    elsif user_data["Portfolio Company"].present? && user_data["Instrument"].blank?
      raise "Portfolio Company Fund Ratio not permitted"
    else
      fund
    end
  end

  def parse_value(value)
    value.to_d
  end

  def format_display_value(value, ratio_name)
    formatted_value = value.to_d.to_f.round(2)

    case ratio_name
    when "XIRR", "Fund Utilization", "Gross Portfolio IRR"
      "#{formatted_value} %"
    else
      "#{formatted_value} x"
    end
  end

  def parse_date(date_string)
    Date.parse(date_string)
  rescue ArgumentError
    raise "Invalid date format for #{date_string}"
  end

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
      value: attrs[:value],
      display_value: attrs[:display_value],
      end_date: attrs[:end_date],
      import_upload_id: attrs[:import_upload].id,
      notes: attrs[:user_data]["Note"],
      label: attrs[:user_data]["Label"]
    )
    fund_ratio.save!
  end

  def create_fund_ratio(attrs)
    # Check if a FundRatio already exists for the same period (end_date)
    existing_fund_ratio = FundRatio.find_by(
      fund_id: attrs[:fund].id,
      entity_id: attrs[:entity].id,
      name: attrs[:user_data]["Ratio Name"],
      owner_type: attrs[:owner].class.name,
      owner_id: attrs[:owner].id,
      end_date: attrs[:end_date]
    )

    raise "Fund Ratio already exists for the given period (end date: #{attrs[:end_date]})" if existing_fund_ratio

    fund_ratio = FundRatio.new(
      fund_id: attrs[:fund].id,
      entity_id: attrs[:entity].id,
      owner_type: attrs[:owner].class.name,
      owner_id: attrs[:owner].id,
      name: attrs[:user_data]["Ratio Name"],
      value: attrs[:value],
      display_value: attrs[:display_value],
      end_date: attrs[:end_date],
      import_upload_id: attrs[:import_upload].id,
      notes: attrs[:user_data]["Note"],
      label: attrs[:user_data]["Label"]
    )

    fund_ratio.capital_commitment_id = attrs[:owner].id if attrs[:owner].is_a?(CapitalCommitment)
    fund_ratio.save!
  end
end
