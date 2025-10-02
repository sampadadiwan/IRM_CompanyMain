class FundDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # fund - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(fund, fund_doc_template, user_id = nil, options: nil)
    Rails.logger.debug { "FundDocGenerator: #{fund}, #{fund_doc_template.name}, #{user_id}, #{options}" }
    @fund_doc_template_name = fund_doc_template.name

    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(fund)
      generate(fund, fund_doc_template_path)
      upload(fund_doc_template, fund, user_id: user_id)
      notify(fund_doc_template, fund, user_id) if user_id
    ensure
      cleanup
    end
  end

  def prepare_context(fund, start_date, end_date)
    {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: fund.entity,
      fund: TemplateDecorator.decorate(fund),
      fund_unit_settings: TemplateDecorator.decorate(fund.fund_unit_settings),
      fund_account_entries: TemplateDecorator.new(fund.fund_account_entries),

      account_entries: TemplateDecorator.new(fund.account_entries),
      account_entries_between_dates: TemplateDecorator.new(fund.account_entries.where(reporting_date: start_date..).where(reporting_date: ..end_date)),
      account_entries_before_end_date: TemplateDecorator.new(fund.account_entries.where(reporting_date: ..end_date)),

      fund_units: TemplateDecorator.new(fund.fund_units),
      fund_units_between_dates: TemplateDecorator.new(fund.fund_units.where(issue_date: start_date..).where(issue_date: ..end_date)),
      fund_units_before_end_date: TemplateDecorator.new(fund.fund_units.where(issue_date: ..end_date)),

      capital_commitments: TemplateDecorator.decorate_collection(fund.capital_commitments),
      amounts: TemplateDecorator.decorate(amounts(fund, capital_commitments, currency, nil, nil)),

      capital_commitments_between_dates: TemplateDecorator.decorate_collection(capital_commitments_between_dates),
      amounts_between_dates: TemplateDecorator.decorate(amounts(fund, capital_commitments_between_dates, currency, start_date, end_date)),

      capital_commitments_before_end_date: TemplateDecorator.decorate_collection(capital_commitments_before_end_date),
      amounts_before_end_date: TemplateDecorator.decorate(amounts(fund, capital_commitments_before_end_date, currency, nil, end_date)),

      capital_remittances: TemplateDecorator.decorate_collection(fund.capital_remittances),
      capital_remittances_between_dates: TemplateDecorator.decorate_collection(fund.capital_remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date)),
      capital_remittances_before_end_date: TemplateDecorator.decorate_collection(fund.capital_remittances.where(remittance_date: ..end_date)),

      capital_remittance_payments: TemplateDecorator.decorate_collection(fund.capital_remittance_payments),
      capital_remittance_payments_between_dates: TemplateDecorator.decorate_collection(fund.capital_remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_remittance_payments_before_end_date: TemplateDecorator.decorate_collection(fund.capital_remittance_payments.where(payment_date: ..end_date)),

      capital_distribution_payments: TemplateDecorator.decorate_collection(fund.capital_distribution_payments),
      capital_distribution_payments_between_dates: TemplateDecorator.decorate_collection(fund.capital_distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_distribution_payments_before_end_date: TemplateDecorator.decorate_collection(fund.capital_distribution_payments.where(payment_date: ..end_date))

    }
  end

  private

  def notify(fund_doc_template, fund, user_id)
    UserAlert.new(user_id:, message: "Document #{fund_doc_template.name} generated for #{fund.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  def generate(fund, start_date, end_date, fund_doc_template_path)
    template = Sablon.template(File.expand_path(fund_doc_template_path))
    context = prepare_context(fund, start_date, end_date)

    # Can we have more than one LP signer ?
    add_image(context, :investor_signature, fund.fund.signature)
    Rails.logger.debug { "Using context #{context} to render template" }

    file_name = generated_file_name(fund)
    convert(template, context, file_name)

    additional_footers = fund.documents.where(name: ["#{@fund_doc_template_name} Footer", "#{@fund_doc_template_name} Signature"])
    additional_headers = fund.documents.where(name: ["#{@fund_doc_template_name} Header", "#{@fund_doc_template_name} Stamp Paper"])
    add_header_footers(fund, file_name, additional_headers, additional_footers)
  end

  def amounts(fund, currency, start_date, end_date)
    remittances = fund.capital_remittances
    remittances = remittances.where(remittance_date: start_date..) if start_date
    remittances = remittances.where(remittance_date: ..end_date) if end_date
    call_amount_cents = remittances.sum(:call_amount_cents)
    collected_amount_cents = remittances.sum(:collected_amount_cents)

    capital_commitments = fund.capital_commitments
    capital_commitments = capital_commitments.where(reporting_date: start_date..) if start_date
    capital_commitments = capital_commitments.where(reporting_date: ..end_date) if end_date
    committed_amount_cents = capital_commitments.sum(:committed_amount_cents)

    distributions = fund.capital_distribution_payments
    distributions = distributions.where(payment_date: start_date..) if start_date
    distributions = distributions.where(payment_date: ..end_date) if end_date
    distribution_amount_cents = distributions.sum(:net_payable_cents)

    OpenStruct.new({
                     committed_amount: Money.new(committed_amount_cents, currency),
                     call_amount: Money.new(call_amount_cents, currency),
                     collected_amount: Money.new(collected_amount_cents, currency),
                     distribution_amount: Money.new(distribution_amount_cents, currency),
                     due_amount: Money.new(call_amount_cents - collected_amount_cents, currency),
                     uncalled_amount: Money.new(committed_amount_cents - call_amount_cents, currency)
                   })
  end
end
