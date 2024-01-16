class KycDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # investor_kyc - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(investor_kyc, doc_template, start_date, end_date, user_id = nil)
    doc_template.file.download do |tempfile|
      doc_template_path = tempfile.path
      create_working_dir(investor_kyc)
      generate(investor_kyc, start_date, end_date, doc_template, doc_template_path)

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

  # doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(investor_kyc, start_date, end_date, doc_template, doc_template_path)
    template = Sablon.template(File.expand_path(doc_template_path))

    currency = investor_kyc.entity.currency
    investor_kyc.entity.currency == "INR" ? investor_kyc.committed_amount.to_i.rupees.humanize : investor_kyc.committed_amount.to_i.to_words.humanize

    capital_commitments = investor_kyc.capital_commitments
    capital_commitments_between_dates = investor_kyc.capital_commitments.where(commitment_date: start_date..).where(commitment_date: ..end_date)
    capital_commitments_before_end_date = investor_kyc.capital_commitments.where(commitment_date: ..end_date)

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      start_date:,
      format_start_date: Time.zone.parse(start_date).strftime("%d %B %Y"),
      end_date:,
      format_end_date: Time.zone.parse(end_date).strftime("%d %B %Y"),
      investor_kyc: TemplateDecorator.decorate(investor_kyc),
      entity: investor_kyc.entity,

      account_entries: TemplateDecorator.new(investor_kyc.account_entries),
      account_entries_between_dates: TemplateDecorator.new(investor_kyc.account_entries.where(reporting_date: start_date..).where(reporting_date: ..end_date)),
      account_entries_before_end_date: TemplateDecorator.new(investor_kyc.account_entries.where(reporting_date: ..end_date)),

      fund_units: TemplateDecorator.new(fund_units(investor_kyc, start_date, end_date)),

      capital_commitments: TemplateDecorator.decorate_collection(capital_commitments),
      amounts: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments, currency, nil, nil)),

      capital_commitments_between_dates: TemplateDecorator.decorate_collection(capital_commitments_between_dates),
      amounts_between_dates: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments_between_dates, currency, start_date, end_date)),

      capital_commitments_before_end_date: TemplateDecorator.decorate_collection(capital_commitments_before_end_date),
      amounts_before_end_date: TemplateDecorator.decorate(amounts(investor_kyc, capital_commitments_before_end_date, currency, nil, end_date)),

      capital_remittances: TemplateDecorator.decorate_collection(investor_kyc.capital_remittances),
      capital_remittances_between_dates: TemplateDecorator.decorate_collection(investor_kyc.capital_remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date)),
      capital_remittances_before_end_date: TemplateDecorator.decorate_collection(investor_kyc.capital_remittances.where(remittance_date: ..end_date)),

      capital_remittance_payments: TemplateDecorator.decorate_collection(investor_kyc.capital_remittance_payments),
      capital_remittance_payments_between_dates: TemplateDecorator.decorate_collection(investor_kyc.capital_remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_remittance_payments_before_end_date: TemplateDecorator.decorate_collection(investor_kyc.capital_remittance_payments.where(payment_date: ..end_date)),

      capital_distribution_payments: TemplateDecorator.decorate_collection(investor_kyc.capital_distribution_payments),
      capital_distribution_payments_between_dates: TemplateDecorator.decorate_collection(investor_kyc.capital_distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_distribution_payments_before_end_date: TemplateDecorator.decorate_collection(investor_kyc.capital_distribution_payments.where(payment_date: ..end_date))

    }

    generate_custom_fields(context, investor_kyc)

    Rails.logger.debug { "Using context #{context.keys} to render template" }
    Rails.logger.debug "Rendering template"

    file_name = generated_file_name(investor_kyc)
    convert(template, context, file_name)

    additional_footers = investor_kyc.documents.where(name: ["#{doc_template.name} Footer", "#{doc_template.name} Signature"])
    additional_headers = investor_kyc.documents.where(name: ["#{doc_template.name} Header", "#{doc_template.name} Stamp Paper"])
    add_header_footers(investor_kyc, file_name, additional_headers, additional_footers)
  end

  def amounts(investor_kyc, ccs, currency, start_date, end_date)
    remittances = CapitalRemittance.where(capital_commitment_id: ccs.pluck(:id))
    remittances = remittances.where(remittance_date: start_date..) if start_date
    remittances = remittances.where(remittance_date: ..end_date) if end_date

    call_amount_cents = remittances.sum(:call_amount_cents)
    collected_amount_cents = remittances.sum(:collected_amount_cents)
    committed_amount_cents = ccs.sum(:committed_amount_cents)

    distributions = CapitalDistributionPayment.where(capital_commitment_id: ccs.pluck(:id))
    distributions = distributions.where(payment_date: start_date..) if start_date
    distributions = distributions.where(payment_date: ..end_date) if end_date

    distribution_amount_cents = distributions.sum(:amount_cents)

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

  def fund_units(investor_kyc, start_date, end_date)
    OpenStruct.new({
                     current: investor_kyc.fund_units.sum(:quantity),
                     before_end_date: investor_kyc.fund_units.where(issue_date: ..end_date).sum(:quantity),
                     between_dates: investor_kyc.fund_units.where(issue_date: ..end_date).where(issue_date: start_date..).sum(:quantity)
                   })
  end

  def generate_custom_fields(context, investor_kyc)
    investor_kyc.properties.each do |k, v|
      context.store "kyc_#{k}", v
    end
  end
end
