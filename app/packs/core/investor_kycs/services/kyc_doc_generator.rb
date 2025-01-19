class KycDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # investor_kyc - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(investor_kyc, doc_template, start_date, end_date, user_id, options: nil)
    doc_template.file.download do |tempfile|
      doc_template_path = tempfile.path
      create_working_dir(investor_kyc)

      fund_id = options.present? ? options[:fund_id] : nil
      generate(investor_kyc, start_date, end_date, doc_template, doc_template_path, fund_id)

      # Use a regular expression to check for the standalone word
      is_soa_doc = doc_template.tag_list.downcase =~ /\b#{Regexp.escape('soa')}\b/

      if is_soa_doc
        upload(doc_template, investor_kyc, Time.zone.parse(start_date).strftime("%d %B,%Y"), Time.zone.parse(end_date).strftime("%d %B,%Y"))
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

    {
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
      capital_distribution_payments_before_end_date: TemplateDecorator.decorate_collection(distribution_payments.where(payment_date: ..end_date))
    }
  end

  # doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(investor_kyc, start_date, end_date, doc_template, doc_template_path, fund_id)
    template = Sablon.template(File.expand_path(doc_template_path))

    context = prepare_context(investor_kyc, start_date, end_date, fund_id)

    add_image(context, :investor_signature, investor_kyc.signature)
    add_image(context, :profile_image, investor_kyc.documents.where(owner_tag: "Profile Image").first&.file)
    add_image(context, :profile_image_2, investor_kyc.documents.where(owner_tag: "Profile Image 2").first&.file) # rubocop:disable Naming/VariableNumber

    generate_custom_fields(context, investor_kyc)

    Rails.logger.debug { "Using context #{context.keys} to render template" }
    Rails.logger.debug "Rendering template"

    file_name = generated_file_name(investor_kyc)
    convert(template, context, file_name)

    additional_footers = investor_kyc.documents.where(name: ["#{doc_template.name} Footer", "#{doc_template.name} Signature"])
    additional_headers = investor_kyc.documents.where(name: ["#{doc_template.name} Header", "#{doc_template.name} Stamp Paper"])
    add_header_footers(investor_kyc, file_name, additional_headers, additional_footers)
  end

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

  def generate_custom_fields(context, investor_kyc)
    investor_kyc.properties.each do |k, v|
      context.store "kyc_#{k}", v
    end
  end
end
