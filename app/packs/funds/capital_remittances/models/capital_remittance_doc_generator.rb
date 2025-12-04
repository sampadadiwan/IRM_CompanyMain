class CapitalRemittanceDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # Initializes the document generator and triggers generation steps
  #
  # @param capital_remittance [CapitalRemittance] the remittance record
  # @param fund_doc_template [FundDocumentTemplate] the Word template to use
  # @param start_date [Date] not used here
  # @param end_date [Date] not used here
  # @param user_id [Integer, nil] ID of the user to notify after generation
  def initialize(capital_remittance, fund_doc_template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug do
      "CapitalRemittanceDocGenerator #{capital_remittance.id}, #{fund_doc_template.name}, #{start_date}, #{end_date}, #{user_id}, #{options}"
    end

    @fund_doc_template_name = fund_doc_template.name

    # Download the Word template and run the document generation pipeline
    fund_doc_template.file.download do |tempfile|
      # skip generation if skip_call_notice is set to yes in capital commitment custom field
      if capital_remittance.capital_commitment.skip_call_notice?
        msg = "Skipping Document Generation for CapitalRemittance as skip_call_notice is set to Yes in the Commitment"
        Rails.logger.info msg
        raise msg
      else
        create_working_dir(capital_remittance)
        generate(capital_remittance, tempfile.path, options)
        upload(fund_doc_template, capital_remittance, nil, nil, nil, final_file_name(@fund_doc_template_name, capital_remittance), user_id: user_id)
        notify(fund_doc_template, capital_remittance, user_id) if user_id
      end
    ensure
      cleanup
    end
  end

  private

  def final_file_name(fund_doc_template_name, capital_remittance)
    "#{fund_doc_template_name} - #{capital_remittance.investor_kyc} - #{capital_remittance.folio_id}"
  end

  # Generate the full document using Sablon and save it to file
  def generate(capital_remittance, template_path, options)
    template = Sablon.template(File.expand_path(template_path))

    # Get the fund state as of a specific date
    fund_as_of = FundAsOf.new(capital_remittance.fund, capital_remittance.remittance_date)
    # Get the capital commitments for LP and GP
    fund_as_of_commitments_lp = fund_as_of.capital_commitments.lp(fund_as_of.id)
    fund_as_of_commitments_gp = fund_as_of.capital_commitments.gp(fund_as_of.id)

    context = base_context(capital_remittance, fund_as_of, options)
    context.merge!(remittance_context(capital_remittance, fund_as_of, fund_as_of_commitments_lp, fund_as_of_commitments_gp))
    context.merge!(distribution_context(capital_remittance, fund_as_of, fund_as_of_commitments_lp, fund_as_of_commitments_gp))

    convert(template, context, generated_file_name(capital_remittance))
  end

  # Core data required for template substitution
  def base_context(capital_remittance, fund_as_of, options)
    capital_commitment = capital_remittance.capital_commitment
    capital_commitment.json_fields["remittance_date"] = capital_remittance.remittance_date
    fund_as_of.json_fields["capital_remittance"] = capital_remittance

    context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      entity: capital_remittance.entity,
      fund: FundTemplateDecorator.decorate(fund_as_of),
      capital_remittance: TemplateDecorator.decorate(capital_remittance),
      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),
      capital_call: TemplateDecorator.decorate(capital_remittance.capital_call),
      due_date: capital_remittance.capital_call.due_date&.strftime("%d %B %Y"),
      call_date: capital_remittance.capital_call.call_date&.strftime("%d %B %Y"),
      capital_commitment: TemplateDecorator.decorate(capital_commitment),
      comm_remittances: TemplateDecorator.decorate(capital_commitment.capital_remittances),
      comm_dist_payments: TemplateDecorator.decorate(capital_commitment.capital_distribution_payments),
      fund_unit_setting: TemplateDecorator.decorate(capital_commitment.fund_unit_setting),
      # All Commitments as of the remittance date
      fund_as_of_commitments: TemplateDecorator.decorate(fund_as_of.capital_commitments)
    }

    call_notice_per_kyc_context(fund_as_of, capital_remittance, capital_commitment, context) if options.present? && options[:call_notice_per_kyc]

    context
  end

  def call_notice_per_kyc_context(fund_as_of, capital_remittance, capital_commitment, context)
    # All remittances with the same kyc
    kyc_capital_remittances = fund_as_of.capital_remittances.includes(:capital_commitment).where(capital_commitment: { investor_kyc_id: capital_commitment.investor_kyc_id }, capital_call_id: capital_remittance.capital_call_id)

    kyc_capital_fee = kyc_capital_remittances.sum(:capital_fee_cents)
    all_capital_fee_breakdowns = kyc_capital_remittances.flat_map { |remittance| remittance.build_fee_structs("capital_fee_audit") }
    # Now sum up the amounts
    kyc_capital_fee_breakdown = capital_remittance.consolidate_fees(all_capital_fee_breakdowns)
    # Store the breakdown in the context
    context.store :kyc_capital_fee_breakdown, kyc_capital_fee_breakdown

    kyc_other_fee = kyc_capital_remittances.sum(:other_fee_cents)
    all_other_fee_breakdowns = kyc_capital_remittances.flat_map { |remittance| remittance.build_fee_structs("other_fee_audit") }
    # Now sum up the amounts
    kyc_other_fee_breakdown = capital_remittance.consolidate_fees(all_other_fee_breakdowns)
    # Store the breakdown in the context
    context.store :kyc_other_fee_breakdown, kyc_other_fee_breakdown

    kyc_investment_amount = kyc_capital_remittances.sum(:investment_amount_cents)
    # For investment_amount, we also need to show the breakdown in the template
    all_investment_breakdowns = kyc_capital_remittances.flat_map { |remittance| remittance.build_fee_structs("investment_amount_audit") }
    # Now sum up the amounts
    kyc_investment_amount_breakdown = capital_remittance.consolidate_fees(all_investment_breakdowns)
    # Store the breakdown in the context
    context.store :kyc_investment_amount_breakdown, kyc_investment_amount_breakdown

    kyc_total_fee = kyc_capital_fee + kyc_other_fee
    kyc_committed_amount = kyc_capital_remittances.sum(:committed_amount_cents)

    kyc_amounts = OpenStruct.new(capital_remittances: TemplateDecorator.decorate(kyc_capital_remittances),
                                 call_amount: Money.new(kyc_capital_remittances.sum(&:call_amount_cents), fund_as_of.currency),
                                 computed_amount: Money.new(kyc_capital_remittances.sum(&:computed_amount_cents), fund_as_of.currency),
                                 capital_fee_amount: Money.new(kyc_capital_fee, fund_as_of.currency),
                                 other_fee_amount: Money.new(kyc_other_fee, fund_as_of.currency),
                                 investment_amount: Money.new(kyc_investment_amount, fund_as_of.currency),
                                 total_fee_amount: Money.new(kyc_total_fee, fund_as_of.currency),
                                 committed_amount: Money.new(kyc_committed_amount, fund_as_of.currency))

    context.store :kyc_amounts, TemplateDecorator.decorate(kyc_amounts)
  end

  # Add remittance breakdowns by LP/GP and current/prior to context
  def remittance_context(remittance, fund_as_of, lp_commitments, gp_commitments)
    lp_ids = lp_commitments.pluck(:id)
    gp_ids = gp_commitments.pluck(:id)
    remittance_date = remittance.remittance_date
    capital_call_id = remittance.capital_call_id

    prior_calls = fund_as_of.capital_calls.where(call_date: ..(remittance_date - 1.day).end_of_day)

    {
      # Commitments of type LP and GP as of the remittance date
      fund_as_of_commitments_lp: TemplateDecorator.decorate(lp_commitments),
      fund_as_of_commitments_gp: TemplateDecorator.decorate(gp_commitments),

      # Remittances of type All, LP and GP as of the remittance date, but prior to the remittance date
      fund_as_of_remittances: TemplateDecorator.decorate(fund_as_of.capital_remittances),
      fund_as_of_remittances_lp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: lp_ids)),
      fund_as_of_remittances_gp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: gp_ids)),

      # Remittances of type All, LP and GP prior to the remittance date
      fund_as_of_prior_remittances: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(remittance_date: ..(remittance_date - 1.day), capital_call_id: prior_calls.pluck(:id))),
      fund_as_of_prior_remittances_lp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: lp_ids, remittance_date: ..(remittance_date - 1.day), capital_call_id: prior_calls.pluck(:id))),
      fund_as_of_prior_remittances_gp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: gp_ids, remittance_date: ..(remittance_date - 1.day), capital_call_id: prior_calls.pluck(:id))),

      # Remittances of type All, LP and GP Exactly On the remittance date
      fund_as_of_curr_remittances: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(remittance_date: remittance_date, capital_call_id: capital_call_id)),
      fund_as_of_curr_remittances_lp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: lp_ids, remittance_date: remittance_date, capital_call_id: capital_call_id)),
      fund_as_of_curr_remittances_gp: TemplateDecorator.decorate(fund_as_of.capital_remittances.where(capital_commitment_id: gp_ids, remittance_date: remittance_date, capital_call_id: capital_call_id))
    }
  end

  # Add capital distribution payment context
  def distribution_context(remittance, fund_as_of, lp_commitments, gp_commitments)
    lp_ids = lp_commitments.pluck(:id)
    gp_ids = gp_commitments.pluck(:id)
    remittance_date = remittance.remittance_date

    {
      # Distribution Payments of type All, LP and GP prior to the remittance date
      fund_as_of_prior_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(payment_date: ..(remittance_date - 1.day))),
      fund_as_of_prior_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids, payment_date: ..(remittance_date - 1.day))),
      fund_as_of_prior_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids, payment_date: ..(remittance_date - 1.day))),

      # Distribution Payments of type All, LP and GP as on the remittance date
      fund_as_of_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments),
      fund_as_of_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids)),
      fund_as_of_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids)),

      # Distribution Payments of type All, LP and GP Exactly On the remittance date
      fund_as_of_curr_dist_payments: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(payment_date: remittance_date)),
      fund_as_of_curr_dist_payments_lp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: lp_ids, payment_date: remittance_date)),
      fund_as_of_curr_dist_payments_gp: TemplateDecorator.decorate(fund_as_of.capital_distribution_payments.where(capital_commitment_id: gp_ids, payment_date: remittance_date))
    }
  end

  # Builds the temp working directory path
  def working_dir_path(capital_remittance)
    "tmp/fund_doc_generator/capital_remittance/#{rand(1_000_000)}/#{capital_remittance.id}"
  end

  # Sends a success alert to the user after document generation
  def notify(fund_doc_template, capital_remittance, user_id)
    UserAlert.new(
      user_id: user_id,
      message: "Document #{fund_doc_template.name} generated for #{capital_remittance.investor_name}. Please refresh the page.",
      level: "success"
    ).broadcast
  end

  # (Unused) Adds formatted amount fields to the context
  def add_amounts(capital_remittance, context)
    currency = capital_remittance.fund.currency
    inr = currency == "INR"

    context.store :call_amount, money_to_currency(capital_remittance.call_amount)
    context.store :call_amount_words, format_words(capital_remittance.call_amount, inr)

    context.store :committed_amount, money_to_currency(capital_remittance.capital_commitment.committed_amount)
    context.store :collected_amount, money_to_currency(capital_remittance.collected_amount)
    context.store :collected_amount_words, format_words(capital_remittance.collected_amount, inr)

    context.store :due_amount, money_to_currency(capital_remittance.due_amount)
    context.store :due_amount_in_words, format_words(capital_remittance.due_amount, inr)

    context.store :capital_fee, money_to_currency(capital_remittance.capital_fee)
    context.store :other_fee, money_to_currency(capital_remittance.other_fee)
    context.store :investment_amount, money_to_currency(capital_remittance.investment_amount)

    # For investment_amount, we also need to show the breakdown in the template
    context.store :investment_amount_breakdown, capital_remittance.build_fee_structs("investment_amount_audit")
    context.store :capital_fee_breakdown, capital_remittance.build_fee_structs("capital_fee_audit")
    context.store :other_fee_breakdown, capital_remittance.build_fee_structs("other_fee_audit")
  end

  # Formats a numeric value to human-readable words based on currency
  def format_words(amount, is_inr)
    is_inr ? amount.to_i.rupees.humanize : amount.to_i.to_words.humanize
  end
end
