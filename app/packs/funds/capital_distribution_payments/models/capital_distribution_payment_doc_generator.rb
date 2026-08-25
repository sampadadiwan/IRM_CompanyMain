class CapitalDistributionPaymentDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase
  include DocGeneratorHelper

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
    @end_date = capital_distribution_payment.payment_date

    # Baseline RSS so we can warn after generation if memory is retained (see ensure below)
    rss_before_mb = log_memory_usage("CapitalDistributionPaymentDocGenerator #{capital_distribution_payment.id} start")

    # Download the Word template and run the document generation pipeline
    fund_doc_template.file.download do |tempfile|
      if capital_distribution_payment.capital_commitment.skip_doc_gen?
        msg = "Skipping Document Generation for CapitalDistributionPayment as skip_doc_gen is set to Yes in the Commitment"
        Rails.logger.info msg
        raise msg
      else
        create_working_dir(capital_distribution_payment)
        generate(capital_distribution_payment, tempfile.path, options, fund_doc_template)
        upload(fund_doc_template, capital_distribution_payment, nil, nil, nil, final_file_name(@fund_doc_template_name, capital_distribution_payment), user_id: user_id, as_of: capital_distribution_payment.payment_date)
        notify(fund_doc_template, capital_distribution_payment, user_id) if user_id
      end
    ensure
      cleanup
      # Warn if this generation grew RSS and a full GC could not release it
      warn_if_memory_retained(rss_before_mb, "CapitalDistributionPaymentDocGenerator #{capital_distribution_payment.id}")
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
  def generate(capital_distribution_payment, template_path, options, fund_doc_template)
    template = Sablon.template(File.expand_path(template_path))

    # Get the fund state as of a specific date
    fund_as_of = FundAsOf.new(capital_distribution_payment.fund, capital_distribution_payment.payment_date)

    # Get the capital commitments for LP and GP
    fund_as_of_commitments_lp = fund_as_of.capital_commitments.lp(fund_as_of.id)
    fund_as_of_commitments_gp = fund_as_of.capital_commitments.gp(fund_as_of.id)

    context = base_context(capital_distribution_payment, fund_as_of, options)
    context.merge!(distribution_context(capital_distribution_payment, fund_as_of, fund_as_of_commitments_lp, fund_as_of_commitments_gp))
    context.merge!(amounts_context(fund_as_of))
    context.merge!(account_entries_breakdown_context(capital_distribution_payment, template_path))

    convert(template, context, generated_file_name(capital_distribution_payment), template_name: @fund_doc_template_name, doc_template: fund_doc_template)
  end

  # Core data required for template substitution
  def base_context(capital_distribution_payment, fund_as_of, options)
    capital_commitment = capital_distribution_payment.capital_commitment
    capital_commitment.json_fields["payment_date"] = capital_distribution_payment.payment_date
    fund_as_of.json_fields["capital_distribution_payment"] = capital_distribution_payment
    investor_kyc = capital_commitment.investor_kyc

    # kyc_commitments_before_end_date and kyc_commitments_between_dates are the same query —
    # build and decorate it once and expose it under both keys, so a template touching both
    # loads the rows once (the relation stays lazy: nothing loads if neither key is used)
    kyc_commitments_to_end_date = TemplateDecorator.decorate_collection(
      investor_kyc.capital_commitments.where(fund_id: capital_distribution_payment.fund_id, commitment_date: ..@end_date)
    )

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_distribution_payment.entity,
      fund: FundTemplateDecorator.decorate(fund_as_of),
      capital_distribution: TemplateDecorator.decorate(capital_distribution_payment.capital_distribution),
      capital_distribution_payment: TemplateDecorator.decorate(capital_distribution_payment),
      investor_kyc: TemplateDecorator.decorate(investor_kyc),
      # Add kyc commitments context
      kyc_commitments: TemplateDecorator.decorate_collection(investor_kyc.capital_commitments.where(fund_id: capital_distribution_payment.fund_id)),
      kyc_commitments_before_end_date: kyc_commitments_to_end_date,
      kyc_commitments_between_dates: kyc_commitments_to_end_date,
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting),
      # All Commitments as of the payment date
      fund_as_of_commitments: TemplateDecorator.decorate(fund_as_of.capital_commitments)
    }

    all_payments = fetch_all_payments(fund_as_of, capital_distribution_payment, options)

    dist_notice_fees_context(
      fund_as_of, all_payments, capital_distribution_payment, capital_commitment, context,
      per_kyc: options.present? && options[:dist_notice_per_kyc]
    )
    # This is only for dumping keys for debugging inside the template
    context.store :context, DocGenContext.new(context)
    context
  end

  # Distribution-wide payments (all folios/investors) as of this payment's date, used to
  # compute fund-wide fee totals in dist_notice_fees_context. A bulk job generates one
  # document per payment in the same distribution, instantiating this generator once per
  # payment — without caching, each instantiation re-queries and re-materializes this same
  # distribution-wide list (O(N^2) across the run for N payments). `options` is the same
  # Hash instance passed to every generator instantiation within one job run (see
  # DocGenJob#generate), so it doubles as a cache scoped to that run. Keyed on as_of_date
  # since FundAsOf#capital_distribution_payments filters payment_date <= as_of_date, and
  # payments within one distribution aren't guaranteed to share the same payment_date.
  def fetch_all_payments(fund_as_of, capital_distribution_payment, options)
    unless options.is_a?(Hash)
      return fund_as_of.capital_distribution_payments
                       .includes(:capital_commitment)
                       .where(capital_distribution_id: capital_distribution_payment.capital_distribution_id)
                       .to_a
    end

    cache = (options[:all_payments_cache] ||= {})
    cache_key = [capital_distribution_payment.capital_distribution_id, fund_as_of.as_of_date]
    cache[cache_key] ||= fund_as_of.capital_distribution_payments
                                   .includes(:capital_commitment)
                                   .where(capital_distribution_id: capital_distribution_payment.capital_distribution_id)
                                   .to_a
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
    # Compute each SQL sum once — committed and drawdown totals were previously
    # queried twice (their own key plus the undrawn-commitments derivation)
    total_committed_cents = fund_as_of.capital_commitments.sum(:committed_amount_cents)
    total_drawdown_cents = fund_as_of.capital_remittances.sum(:call_amount_cents)

    {
      total_committed_cash: Money.new(total_committed_cents, currency),
      total_distribution_cash: Money.new(fund_as_of.capital_distribution_payments.sum("gross_payable_cents - reinvestment_with_fees_cents"), currency),
      total_reinvestment: Money.new(fund_as_of.capital_distribution_payments.sum(:reinvestment_with_fees_cents), currency),
      total_drawdowns: Money.new(total_drawdown_cents, currency),
      total_undrawn_commitments: Money.new(total_committed_cents - total_drawdown_cents, currency)
    }
  end

  # Computes fee breakdowns for the current folio and, optionally, the KYC level.
  # Always stores folio-level keys (folio_* and current_payment_*).
  # When per_kyc: true, also stores KYC-level keys (dist_* and kyc_*) and kyc_amounts.
  # dist_fees (fund-wide totals) are computed once per fee type and shared between both levels.
  def dist_notice_fees_context(fund_as_of, all_payments, capital_distribution_payment, capital_commitment, context, per_kyc: false)
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

  # Build account entries breakdown context for template substitution
  # Extracts all merge fields starting with 'aes_' or 'aescumulative_' from the template,
  # fetches detailed account entry breakdowns for KYC-level commitments, and decorates them.
  # Each breakdown field becomes a key in the returned context hash.
  #
  # @param capital_distribution_payment [CapitalDistributionPayment] The distribution payment record
  # @param template_path [String] Path to the .docx template file
  # @return [Hash<Symbol, Array<TemplateDecorator>>] Hash where:
  #   - Keys: Field names as symbols (e.g., :aes_revenue, :aescumulative_gains)
  #   - Values: Decorated collections of breakdown items. Each item is a DocGeneratorHelper::AccountEntryBreakdown with:
  #     - name [String] Display name from distribution fees or account entry name
  #     - reporting_date [Date] When the entry was recorded
  #     - folio_id [String] Folio identifier
  #     - amount [Money] The amount in the fund's currency
  #     - entry_type [String] The type of account entry (e.g., fee type)
  #
  # Returns an empty hash if no aes_ fields are found in the template.
  def account_entries_breakdown_context(capital_distribution_payment, template_path)
    context = {}
    aes_fields = extract_merge_fields(template_path, [/^aes_/, /^aescumulative_/])

    return context if aes_fields.blank?

    capital_commitment = capital_distribution_payment.capital_commitment
    currency = capital_distribution_payment.fund.currency
    kyc_commitments = capital_commitment.investor_kyc.capital_commitments.where(fund_id: capital_distribution_payment.fund_id)

    # The account entries breakdown was the prime suspect for memory bloat — log around it
    log_memory_usage("account_entries_breakdown #{capital_distribution_payment.id} start (#{aes_fields.size} aes fields)")

    aes_fields.each do |field|
      breakdown = fetch_account_entries_breakdown(
        field,
        capital_distribution_payment.fund.account_entries,
        :aes_breakdown,
        capital_distribution_payment.payment_date,
        currency,
        capital_commitment,
        kyc_commitments,
        capital_distribution_payment.capital_distribution
      )

      context[field.to_sym] = breakdown.present? ? TemplateDecorator.decorate_collection(breakdown) : []
    end

    log_memory_usage("account_entries_breakdown #{capital_distribution_payment.id} done")

    context
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
