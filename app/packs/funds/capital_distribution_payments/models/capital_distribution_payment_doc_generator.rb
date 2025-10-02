class CapitalDistributionPaymentDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # Initializes the document generator and triggers generation steps
  #
  # @param capital_distribution_payment [CapitalDistributionPayment] the distribution payment record
  # @param fund_doc_template [FundDocumentTemplate] the Word template to use
  # @param start_date [Date] not used here
  # @param end_date [Date] not used here
  # @param user_id [Integer, nil] ID of the user to notify after generation
  def initialize(capital_distribution_payment, fund_doc_template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug do
      "CapitalDistributionPaymentDocGenerator #{capital_distribution_payment.id}, #{fund_doc_template.name}, #{start_date}, #{end_date}, #{user_id}, #{options}"
    end

    @fund_doc_template_name = fund_doc_template.name

    # Download the Word template and run the document generation pipeline
    fund_doc_template.file.download do |tempfile|
      create_working_dir(capital_distribution_payment)
      generate(capital_distribution_payment, tempfile.path)
      upload(fund_doc_template, capital_distribution_payment, user_id: user_id)
      notify(fund_doc_template, capital_distribution_payment, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  # Generate the full document using Sablon and save it to file
  def generate(capital_distribution_payment, template_path)
    template = Sablon.template(File.expand_path(template_path))

    # Get the fund state as of a specific date
    fund_as_of = FundAsOf.new(capital_distribution_payment.fund, capital_distribution_payment.payment_date)

    # Get the capital commitments for LP and GP
    fund_as_of_commitments_lp = fund_as_of.capital_commitments.lp(fund_as_of.id)
    fund_as_of_commitments_gp = fund_as_of.capital_commitments.gp(fund_as_of.id)

    context = base_context(capital_distribution_payment, fund_as_of)
    context.merge!(distribution_context(capital_distribution_payment, fund_as_of, fund_as_of_commitments_lp, fund_as_of_commitments_gp))
    context.merge!(amounts_context(fund_as_of))

    convert(template, context, generated_file_name(capital_distribution_payment))
  end

  # Core data required for template substitution
  def base_context(capital_distribution_payment, fund_as_of)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_commitment.json_fields["payment_date"] = capital_distribution_payment.payment_date
    fund_as_of.json_fields["capital_distribution_payment"] = capital_distribution_payment

    {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_distribution_payment.entity,
      fund: FundTemplateDecorator.decorate(fund_as_of),
      capital_distribution: TemplateDecorator.decorate(capital_distribution_payment.capital_distribution),
      capital_distribution_payment: TemplateDecorator.decorate(capital_distribution_payment),
      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting),
      # All Commitments as of the payment date
      fund_as_of_commitments: TemplateDecorator.decorate(fund_as_of.capital_commitments)
    }
  end

  # Add capital distribution payment context
  def distribution_context(dist_payment, fund_as_of, lp_commitments, gp_commitments)
    lp_ids = lp_commitments.pluck(:id)
    gp_ids = gp_commitments.pluck(:id)
    dist_payment_date = dist_payment.payment_date

    {
      # Distribution Payments of type All, LP and GP prior to the dist_payment_date
      fund_as_of_prior_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(payment_date: ..(dist_payment_date - 1.day))),
      fund_as_of_prior_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids, payment_date: ..(dist_payment_date - 1.day))),
      fund_as_of_prior_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids, payment_date: ..(dist_payment_date - 1.day))),

      # Distribution Payments of type All, LP and GP as on the dist_payment_date
      fund_as_of_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments),
      fund_as_of_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids)),
      fund_as_of_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids)),

      # Distribution Payments of type All, LP and GP Exactly On the dist_payment_date
      fund_as_of_curr_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(payment_date: dist_payment_date)),
      fund_as_of_curr_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids, payment_date: dist_payment_date)),

      fund_as_of_curr_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids, payment_date: dist_payment_date))
      # comm_dist_payments: TemplateDecorator.decorate(distribution_payment.capital_commitment.capital_distribution_payments)
    }
  end

  # Add amounts from the fund_as_of to the context
  def amounts_context(fund_as_of)
    currency = fund_as_of.currency
    {
      total_committed_cash: Money.new(fund_as_of.capital_commitments.sum(:committed_amount_cents), currency),
      total_distribution_cash: Money.new(fund_as_of.capital_distribution_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), currency),
      total_reinvestment: Money.new(fund_as_of.capital_distribution_payments.sum(:reinvestment_with_fees_cents), currency),
      total_drawdowns: Money.new(fund_as_of.capital_remittances.sum(:call_amount_cents), currency),
      total_undrawn_commitments: Money.new(fund_as_of.capital_commitments.sum(:committed_amount_cents) - fund_as_of.capital_remittances.sum(:call_amount_cents), currency)
    }
  end

  # Builds the temp working directory path
  def working_dir_path(capital_distribution_payment)
    "tmp/fund_doc_generator/capital_distribution_payment/#{rand(1_000_000)}/#{capital_distribution_payment.id}"
  end

  # Sends a success alert to the user after document generation
  def notify(fund_doc_template, capital_distribution_payment, user_id)
    UserAlert.new(
      user_id: user_id,
      message: "Document #{fund_doc_template.name} generated for #{capital_distribution_payment.investor_name}. Please refresh the page.",
      level: "success"
    ).broadcast
  end
end
