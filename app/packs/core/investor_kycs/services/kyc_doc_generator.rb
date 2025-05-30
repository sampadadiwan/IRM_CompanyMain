class KycDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # Parse options to extract fund_id, capital_commitment_id, and file_name
  def parse_options(options)
    fund_id = options[:fund_id]
    capital_commitment_id = options[:capital_commitment_id]
    file_name = nil

    # If capital_commitment_id is present, find the capital commitment and generate a file name
    if capital_commitment_id.present?
      capital_commitment = CapitalCommitment.find(capital_commitment_id)
      file_name = generated_file_name(capital_commitment)
    end

    # Return the parsed values as an array
    [fund_id, capital_commitment_id, file_name]
  end

  # investor_kyc - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(investor_kyc, doc_template, start_date, end_date, user_id, options: {})
    Rails.logger.debug { "KycDocGenerator #{investor_kyc.id}, #{doc_template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    doc_template.file.download do |tempfile|
      # Save the document template to a temporary file
      doc_template_path = tempfile.path
      # Create a working directory for the document generation
      create_working_dir(investor_kyc)

      # Generate the document
      fund_id, capital_commitment_id, file_name = parse_options(options)
      generate(investor_kyc, start_date, end_date, doc_template, doc_template_path, fund_id, file_name:)

      # Use a regular expression to check if this is an SOA template
      is_soa_template = (doc_template.tag_list&.downcase =~ /\b#{Regexp.escape('soa')}\b/) || (doc_template.owner_tag&.downcase =~ /\b#{Regexp.escape('soa')}\b/)

      if is_soa_template
        # Now in certain cases the doc is generated for a KYC and in certain cases for a commitment
        # 1. The normal case is when the doc is generated for a KYC, mostly for Angel funds. In this case, we want to attach it to the KYC
        # 2. The other case is when the doc is generated for a commitment, when we want to generate the SOA at the Investing Entity level, but is triggered at the commitment level. In this case we need to attach it to the commitment
        if capital_commitment_id.present?
          # Attach the generated document to the capital commitment
          capital_commitment = CapitalCommitment.find(options[:capital_commitment_id])
          upload(doc_template, capital_commitment, Time.zone.parse(start_date).strftime("%d %B,%Y"), Time.zone.parse(end_date).strftime("%d %B,%Y"))
        else
          # Attach the generated document to the investor KYC
          upload(doc_template, investor_kyc, Time.zone.parse(start_date).strftime("%d %B,%Y"), Time.zone.parse(end_date).strftime("%d %B,%Y"))
        end
      elsif options.present? && options[:capital_commitment_id].present?
        capital_commitment = CapitalCommitment.find(options[:capital_commitment_id])
        upload(doc_template, capital_commitment)
      # Attach the generated document to the capital commitment
      else
        upload(doc_template, investor_kyc)
      end
      notify(doc_template, investor_kyc, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def notify(doc_template, investor_kyc, user_id)
    send_notification("#{doc_template.name} generated for #{investor_kyc.full_name}. Please refresh the page.", user_id)
  end

  def prepare_context(investor_kyc, start_date, end_date, fund_id)
    # Get the currency of the investor's entity
    currency = investor_kyc.entity.currency

    # Convert committed amount to words based on currency
    investor_kyc.entity.currency == "INR" ? investor_kyc.committed_amount.to_i.rupees.humanize : investor_kyc.committed_amount.to_i.to_words.humanize

    # Get all capital commitments for the investor, including associated fund and investor
    capital_commitments = investor_kyc.capital_commitments.includes(:fund, :investor)
    # Filter capital commitments by fund_id if provided
    capital_commitments = capital_commitments.where(fund_id: fund_id) if fund_id

    # Get capital commitments between the start and end dates
    capital_commitments_between_dates = capital_commitments.where(commitment_date: start_date..).where(commitment_date: ..end_date)
    # Get capital commitments before the end date
    capital_commitments_before_end_date = capital_commitments.where(commitment_date: ..end_date)

    # Get all capital remittances for the investor, including associated capital commitment, capital call, and fund, ordered by remittance date
    remittances = investor_kyc.capital_remittances.includes(:capital_commitment, :capital_call, :fund).order(:remittance_date)
    # Filter remittances by fund_id if provided
    remittances = remittances.where(fund_id: fund_id) if fund_id

    # Get all capital distribution payments for the investor, including associated capital commitment, fund, and capital distribution
    distribution_payments = investor_kyc.capital_distribution_payments.includes(:capital_commitment, :fund, :capital_distribution)
    # Filter distribution payments by fund_id if provided
    distribution_payments = distribution_payments.where(fund_id: fund_id) if fund_id

    account_entries = investor_kyc.account_entries
    account_entries = account_entries.where(fund_id: fund_id) if fund_id

    capital_remittance_payments = investor_kyc.capital_remittance_payments
    capital_remittance_payments = capital_remittance_payments.where(fund_id: fund_id) if fund_id

    context = {
      # Set the current date in the context
      date: Time.zone.today.strftime("%d %B %Y"),
      start_date:,
      format_start_date: Time.zone.parse(start_date).strftime("%d %B %Y"),
      end_date:,
      format_end_date: Time.zone.parse(end_date).strftime("%d %B %Y"),
      investor_kyc: TemplateDecorator.decorate(investor_kyc),
      entity: investor_kyc.entity,

      # Add account entries for the investor
      account_entries: TemplateDecorator.new(account_entries),
      account_entries_between_dates: TemplateDecorator.new(account_entries.where(reporting_date: start_date..).where(reporting_date: ..end_date)),
      account_entries_before_end_date: TemplateDecorator.new(account_entries.where(reporting_date: ..end_date)),

      fund_units: TemplateDecorator.new(fund_units(investor_kyc, start_date, end_date, fund_id)),
      agreement_unit_setting: TemplateDecorator.new(investor_kyc.agreement_unit_setting),

      capital_commitments: TemplateDecorator.decorate_collection(capital_commitments),
      amounts: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments, currency, nil, nil, fund_id)),

      capital_commitments_between_dates: TemplateDecorator.decorate_collection(capital_commitments_between_dates),
      amounts_between_dates: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments_between_dates, currency, start_date, end_date, fund_id)),

      capital_commitments_before_end_date: TemplateDecorator.decorate_collection(capital_commitments_before_end_date),
      amounts_before_end_date: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments_before_end_date, currency, nil, end_date, fund_id)),

      capital_remittances: TemplateDecorator.decorate_collection(remittances),
      capital_remittances_between_dates: TemplateDecorator.decorate_collection(remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date)),
      capital_remittances_before_end_date: TemplateDecorator.decorate_collection(remittances.where(remittance_date: ..end_date)),

      capital_remittance_payments: TemplateDecorator.decorate_collection(capital_remittance_payments),
      capital_remittance_payments_between_dates: TemplateDecorator.decorate_collection(capital_remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_remittance_payments_before_end_date: TemplateDecorator.decorate_collection(capital_remittance_payments.where(payment_date: ..end_date)),

      capital_distribution_payments: TemplateDecorator.decorate_collection(distribution_payments),
      capital_distribution_payments_between_dates: TemplateDecorator.decorate_collection(distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_distribution_payments_before_end_date: TemplateDecorator.decorate_collection(distribution_payments.where(payment_date: ..end_date)),
      portfolio_company_cumulative_folio_entries: TemplateDecorator.decorate_collection(portfolio_company_cumulative_folio_entries(investor_kyc, start_date, end_date))
    }

    if fund_id.present?
      fund_account_entries = AccountEntry.fund_entries.where(fund_id: fund_id)
      context[:fund_account_entries] = TemplateDecorator.new(fund_account_entries)
      context[:fund_account_entries_between_dates] = TemplateDecorator.new(fund_account_entries.where(reporting_date: start_date..).where(reporting_date: ..end_date))
      context[:fund_account_entries_before_end_date] = TemplateDecorator.new(fund_account_entries.where(reporting_date: ..end_date))
    end

    context
  end

  # doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  # rubocop:disable Metrics/ParameterLists
  def generate(investor_kyc, start_date, end_date, doc_template, doc_template_path, fund_id, file_name: nil)
    template = Sablon.template(File.expand_path(doc_template_path))

    context = prepare_context(investor_kyc, start_date, end_date, fund_id)
    add_reporting_entries(context, investor_kyc, start_date, end_date, fund_id)

    add_image(context, :investor_signature, investor_kyc.signature)
    add_image(context, :profile_image, investor_kyc.documents.where(owner_tag: "Profile Image").first&.file)
    add_image(context, :profile_image_2, investor_kyc.documents.where(owner_tag: "Profile Image 2").first&.file) # rubocop:disable Naming/VariableNumber

    generate_custom_fields(context, investor_kyc)

    Rails.logger.debug { "Using context #{context.keys} to render template" }
    Rails.logger.debug "Rendering template"

    file_name ||= generated_file_name(investor_kyc)
    convert(template, context, file_name)

    additional_footers = investor_kyc.documents.where(name: ["#{doc_template.name} Footer", "#{doc_template.name} Signature"])
    additional_headers = investor_kyc.documents.where(name: ["#{doc_template.name} Header", "#{doc_template.name} Stamp Paper"])
    add_header_footers(investor_kyc, file_name, additional_headers, additional_footers)
  end
  # rubocop:enable Metrics/ParameterLists

  def amounts(investor_kyc, ccs, currency, start_date, end_date, fund_id)
    remittances = investor_kyc.capital_remittances.where(capital_commitment_id: ccs.pluck(:id))
    remittances = remittances.where(fund_id: fund_id) if fund_id
    remittances = remittances.where(remittance_date: start_date..) if start_date
    remittances = remittances.where(remittance_date: ..end_date) if end_date

    call_amount_cents = remittances.sum(:call_amount_cents)
    collected_amount_cents = remittances.sum(:collected_amount_cents)
    committed_amount_cents = ccs.sum(:committed_amount_cents)

    distributions = investor_kyc.capital_distribution_payments.where(capital_commitment_id: ccs.pluck(:id))
    distributions = distributions.where(fund_id: fund_id) if fund_id
    distributions = distributions.where(payment_date: start_date..) if start_date
    distributions = distributions.where(payment_date: ..end_date) if end_date

    distribution_amount_cents = distributions.sum(:gross_payable_cents)

    OpenStruct.new({
                     committed_amount: Money.new(committed_amount_cents, currency),
                     call_amount: Money.new(call_amount_cents, currency),
                     collected_amount: Money.new(collected_amount_cents, currency),
                     distribution_amount: Money.new(distribution_amount_cents, currency),
                     due_amount: Money.new(call_amount_cents - collected_amount_cents, currency),
                     uncalled_amount: Money.new(committed_amount_cents - call_amount_cents, currency),
                     face_value_for_redemption: Money.new(investor_kyc.face_value_for_redemption(start_date:, end_date:).cents, currency),
                     custom_uncalled_amount: Money.new(investor_kyc.custom_committed_amount.cents - call_amount_cents + investor_kyc.face_value_for_redemption(start_date:, end_date:).cents, currency)
                   })
  end

  def fund_units(investor_kyc, start_date, end_date, fund_id)
    fund_units = investor_kyc.fund_units
    fund_units = fund_units.where(fund_id: fund_id) if fund_id

    OpenStruct.new({
                     current: fund_units.sum(:quantity),
                     before_end_date: fund_units.where(issue_date: ..end_date).sum(:quantity),
                     between_dates: fund_units.where(issue_date: ..end_date).where(issue_date: start_date..).sum(:quantity)
                   })
  end

  # Add the reporting entries for the investor kyc, note that since a KYC can be linked to multiple commitments, there could be multiple account entries with the same name (ex Setup Fees, one for each commitment), so sum them (Ex Sum of Setup Fees) before adding to the context
  def add_reporting_entries(context, investor_kyc, start_date, end_date, fund_id)
    raes = investor_kyc.account_entries.where(reporting_date: start_date..end_date, rule_for: "Reporting")
    # Filter by fund id if provided
    raes = raes.where(fund_id: fund_id) if fund_id.present?

    first_commitment = investor_kyc.capital_commitments.first
    raes.group_by { |ae| [ae.name, ae.entry_type] }.each do |name_entry_type, aes|
      # Sum the amounts for the same name and entry type and create another dummy entry type
      total_amount_cents = aes.sum(&:amount_cents)
      ae = AccountEntry.new(name: name_entry_type[0], entry_type: name_entry_type[1], amount_cents: total_amount_cents, capital_commitment: first_commitment, fund: first_commitment&.fund, reporting_date: aes[0].reporting_date)
      context["reporting_#{ae.template_field_name}"] = TemplateDecorator.decorate(ae)
    end

    if fund_id.present?
      # make sure to filter by fund id
      fraes = AccountEntry.fund_entries.where(fund_id: fund_id, reporting_date: start_date..end_date, rule_for: "Reporting")
      fraes.group_by { |ae| [ae.name, ae.entry_type] }.each do |name_entry_type, aes|
        total_amount_cents = aes.sum(&:amount_cents)
        ae = AccountEntry.new(name: name_entry_type[0], entry_type: name_entry_type[1], amount_cents: total_amount_cents, fund_id: fund_id, reporting_date: aes[0].reporting_date)
        context["reporting_fund_#{ae.template_field_name}"] = TemplateDecorator.decorate(ae)
      end
    end
  end

  def portfolio_company_cumulative_folio_entries(investor_kyc, start_date, end_date, entry_type: "Portfolio Allocation")
    raes = investor_kyc.account_entries.where(reporting_date: start_date..end_date, rule_for: "Reporting", entry_type: entry_type).where(parent_type: "Investor").includes(parent: :portfolio_company)

    first_commitment = investor_kyc.capital_commitments.first
    portfolio_company_entries_map = {}

    raes.group_by { |ae| [ae.name, ae.parent.investor_name] }.each do |ae_name_investor_name, aes|
      portfolio_company_name = ae_name_investor_name[1]
      ae_key = ae_name_investor_name[0].strip.parameterize.underscore

      portfolio_company_entry = portfolio_company_entries_map[portfolio_company_name]
      portfolio_company_entry ||= OpenStruct.new(portfolio_company: portfolio_company_name)

      total_amount_cents = aes.sum(&:amount_cents)
      portfolio_company_entry[ae_key] = Money.new(total_amount_cents, first_commitment.fund.currency)
      portfolio_company_entries_map[portfolio_company_name] = portfolio_company_entry
    end
    portfolio_company_entries_map.values
  end

  def generate_custom_fields(context, investor_kyc)
    investor_kyc.properties.each do |k, v|
      context.store "kyc_#{k}", v
    end
  end
end
