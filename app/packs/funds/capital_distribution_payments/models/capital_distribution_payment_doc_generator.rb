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
      if capital_distribution_payment.capital_commitment.skip_call_notice?
        msg = "Skipping Document Generation for CapitalDistributionPayment as skip_call_notice is set to Yes in the Commitment"
        Rails.logger.info msg
        raise msg
      else
        create_working_dir(capital_distribution_payment)
        generate(capital_distribution_payment, tempfile.path, options)
        upload(fund_doc_template, capital_distribution_payment, nil, nil, nil, final_file_name(@fund_doc_template_name, capital_distribution_payment), user_id: user_id)
        notify(fund_doc_template, capital_distribution_payment, user_id) if user_id
      end
    ensure
      cleanup
    end
  end

  def final_file_name(fund_doc_template_name, capital_distribution_payment)
    "#{fund_doc_template_name} - #{capital_distribution_payment.investor_kyc} - #{capital_distribution_payment.folio_id}"
  end

  # Typed value object for aggregated KYC-level distribution amounts.
  # Replaces OpenStruct for explicit shape and better performance.
  # skipping folio_amount as the folio currency can be diff for diff payments
  KycAmounts = Struct.new(
    :kyc_dist_payments, :income, :cost_of_investment, :net_of_account_entries,
    :net_payable, :income_with_fees, :cost_of_investment_with_fees,
    :reinvestment, :reinvestment_with_fees, :gross_payable,
    :gross_of_account_entries,
    keyword_init: true
  )

  private

  # Generate the full document using Sablon and save it to file
  def generate(capital_distribution_payment, template_path, options)
    template = Sablon.template(File.expand_path(template_path))

    # Get the fund state as of a specific date
    fund_as_of = FundAsOf.new(capital_distribution_payment.fund, capital_distribution_payment.payment_date)

    # Get the capital commitments for LP and GP
    fund_as_of_commitments_lp = fund_as_of.capital_commitments.lp(fund_as_of.id)
    fund_as_of_commitments_gp = fund_as_of.capital_commitments.gp(fund_as_of.id)

    context = base_context(capital_distribution_payment, fund_as_of, options)
    context.merge!(distribution_context(capital_distribution_payment, fund_as_of, fund_as_of_commitments_lp, fund_as_of_commitments_gp))
    context.merge!(amounts_context(fund_as_of))

    convert(template, context, generated_file_name(capital_distribution_payment))
  end

  # Core data required for template substitution
  def base_context(capital_distribution_payment, fund_as_of, options)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_commitment.json_fields["payment_date"] = capital_distribution_payment.payment_date
    fund_as_of.json_fields["capital_distribution_payment"] = capital_distribution_payment

    context = {
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

    all_payments = fund_as_of.capital_distribution_payments
                             .includes(:capital_commitment)
                             .where(capital_distribution_id: capital_distribution_payment.capital_distribution_id)
                             .to_a

    dist_notice_fees_context(
      fund_as_of, all_payments, capital_distribution_payment, capital_commitment, context,
      per_kyc: options.present? && options[:dist_notice_per_kyc]
    )
    # This is only for dumping keys for debugging inside the template
    context.store :context, DocGenContext.new(context)
    context
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

  # Computes fee breakdowns for the current folio and, optionally, the KYC level.
  # Always stores folio-level keys (folio_* and current_payment_*).
  # When per_kyc: true, also stores KYC-level keys (dist_* and kyc_*) and kyc_amounts.
  # dist_fees (fund-wide totals) are computed once per fee type and shared between both levels.
  def dist_notice_fees_context(fund_as_of, all_payments, capital_distribution_payment, capital_commitment, context, per_kyc: false) # rubocop:disable Metrics/CyclomaticComplexity, Metrics/MethodLength
    current_payment = all_payments.select { |p| p.id == capital_distribution_payment.id }

    # Partition KYC payments in Ruby to avoid an extra DB query (all_payments already loaded)
    if per_kyc
      kyc_id       = capital_commitment.investor_kyc_id
      kyc_payments = all_payments.select { |p| p.capital_commitment.investor_kyc_id == kyc_id }
    end

    # Build and group all audit structs up front — one flat_map pass per set
    grouped_dist     = CapitalDistributionPayment.group_by_fee_type(all_payments.flat_map(&:build_fee_structs))
    grouped_current  = CapitalDistributionPayment.group_by_fee_type(current_payment.flat_map(&:build_fee_structs))
    grouped_kyc      = CapitalDistributionPayment.group_by_fee_type(kyc_payments.flat_map(&:build_fee_structs)) if per_kyc

    DistributionFee::KYC_FEE_TYPE_KEYS.each do |fee_type, key|
      # Consolidate fees by name for distribution-level
      dist_fees    = CapitalDistributionPayment.consolidate_fees(grouped_dist[fee_type] || [])
      # Consolidate fees by name for current payment-level
      current_fees = CapitalDistributionPayment.consolidate_fees(grouped_current[fee_type] || [])
      dist_map     = dist_fees.index_by(&:name)

      # Annotate each fee with the fund-wide total for its name
      current_fees.each { |fee| fee.total_amount_across_folios = dist_map[fee.name]&.amount }
      context.store :"dist_#{key}_breakdown", TemplateDecorator.decorate_collection(dist_fees)
      context.store :"current_payment_#{key}_breakdown", TemplateDecorator.decorate_collection(current_fees)

      next unless per_kyc

      # Consolidate fees by name for kyc-level and annotate with distribution-level totals
      kyc_fees = CapitalDistributionPayment.consolidate_fees(grouped_kyc[fee_type] || [])
      kyc_fees.each { |fee| fee.total_amount_across_folios = dist_map[fee.name]&.amount }
      context.store :"kyc_#{key}_breakdown", TemplateDecorator.decorate_collection(kyc_fees)
    end

    return unless per_kyc

    # Aggregate all monetary fields for kyc_amounts in a single pass
    currency = fund_as_of.currency
    amount_fields = %i[
      income cost_of_investment net_of_account_entries net_payable
      income_with_fees cost_of_investment_with_fees reinvestment
      reinvestment_with_fees gross_payable gross_of_account_entries
    ]

    sums = kyc_payments.each_with_object(Hash.new(0)) do |payment, totals|
      amount_fields.each { |field| totals[field] += payment.public_send(:"#{field}_cents") }
    end

    kyc_amounts = KycAmounts.new(
      kyc_dist_payments: TemplateDecorator.decorate(kyc_payments),
      income: Money.new(sums[:income], currency),
      cost_of_investment: Money.new(sums[:cost_of_investment], currency),
      net_of_account_entries: Money.new(sums[:net_of_account_entries], currency),
      net_payable: Money.new(sums[:net_payable], currency),
      income_with_fees: Money.new(sums[:income_with_fees], currency),
      cost_of_investment_with_fees: Money.new(sums[:cost_of_investment_with_fees], currency),
      reinvestment: Money.new(sums[:reinvestment], currency),
      reinvestment_with_fees: Money.new(sums[:reinvestment_with_fees], currency),
      gross_payable: Money.new(sums[:gross_payable], currency),
      gross_of_account_entries: Money.new(sums[:gross_of_account_entries], currency)
    )

    context.store :kyc_amounts, TemplateDecorator.decorate(kyc_amounts)
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
