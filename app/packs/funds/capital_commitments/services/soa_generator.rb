class SoaGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  # capital_commitment - we want to generate the document for this CapitalCommitment
  # fund document template - the document are we using as  template for generation
  def initialize(capital_commitment, fund_doc_template, start_date, end_date, user_id = nil, _options: nil)
    if capital_commitment.investor_kyc
      # Download the fund document template file
      fund_doc_template.file.download do |tempfile|
        fund_doc_template_path = tempfile.path

        # Create a working directory for the capital commitment
        create_working_dir(capital_commitment)

        # Generate the SOA document
        generate(capital_commitment, start_date, end_date, fund_doc_template_path)

        # Upload the generated document
        upload(fund_doc_template, capital_commitment, Time.zone.parse(start_date).strftime("%d %B,%Y"), Time.zone.parse(end_date).strftime("%d %B,%Y"), capital_commitment.soa_folder)

        # Notify the user if user_id is provided
        notify(fund_doc_template, capital_commitment, user_id) if user_id
      ensure
        # Cleanup temporary files and directories
        cleanup
      end
    else
      msg = "SOA generation failed. KYC not found for #{capital_commitment.investor_name}."
      send_notification(msg, user_id) if user_id
      Rails.logger.debug msg
    end
  end

  private

  def notify(fund_doc_template, capital_commitment, user_id)
    msg = "SOA #{fund_doc_template.name} generated for #{capital_commitment.investor_name}. Please refresh the page."
    send_notification(msg, user_id)
  end

  def prepare_context(capital_commitment, start_date, end_date)
    capital_commitment.start_date = Time.zone.parse(start_date)
    capital_commitment.end_date = Time.zone.parse(end_date)

    amount_in_words = capital_commitment.fund.currency == "INR" ? capital_commitment.committed_amount.to_i.rupees.humanize : capital_commitment.committed_amount.to_i.to_words.humanize
    remittances = capital_commitment.capital_remittances.includes(:capital_commitment, :capital_call, :fund).order(:remittance_date)
    remittance_payments = capital_commitment.capital_remittance_payments.includes(:capital_remittance, :fund).order(:payment_date)

    distribution_payments = capital_commitment.capital_distribution_payments.includes(:capital_commitment, :fund, :capital_distribution).order(:payment_date)
    account_entries = capital_commitment.account_entries.includes(:capital_commitment, :fund)
    fund_ratios = capital_commitment.fund_ratios.includes(:capital_commitment, :fund)
    adjustments = capital_commitment.commitment_adjustments.includes(:capital_commitment, :fund)

    fund_currency = capital_commitment.fund.currency
    folio_currency = capital_commitment.folio_currency

    committed_amounts_before_start_date = Money.new(capital_commitment.committed_amount_cents_before(start_date), fund_currency)
    committed_amounts_before_end_date = Money.new(capital_commitment.committed_amount_cents_before(end_date), fund_currency)
    committed_amounts_between_dates = committed_amounts_before_end_date - committed_amounts_before_start_date

    committed_folio_amounts_before_start_date = Money.new(capital_commitment.committed_amount_cents_before(start_date), folio_currency)
    committed_folio_amounts_before_end_date = Money.new(capital_commitment.committed_amount_cents_before(end_date), folio_currency)
    committed_folio_amounts_between_dates = committed_folio_amounts_before_end_date - committed_amounts_before_start_date

    @context = {
      date: Time.zone.today.strftime("%d %B %Y"),
      start_date:,
      format_start_date: Time.zone.parse(start_date).strftime("%d %B %Y"),
      end_date:,
      format_end_date: Time.zone.parse(end_date).strftime("%d %B %Y"),
      capital_commitment: CapitalCommitmentTemplateDecorator.decorate(capital_commitment),
      # Sometimes we need committed_amounts before start and end date
      committed_amounts: TemplateDecorator.decorate(OpenStruct.new(
                                                      before_start_date: committed_amounts_before_start_date,
                                                      before_end_date: committed_amounts_before_end_date,
                                                      between_dates: committed_amounts_between_dates
                                                    )),

      committed_folio_amounts: TemplateDecorator.decorate(OpenStruct.new(
                                                            before_start_date: committed_folio_amounts_before_start_date,
                                                            before_end_date: committed_folio_amounts_before_end_date,
                                                            between_dates: committed_folio_amounts_between_dates
                                                          )),

      entity: capital_commitment.entity,
      fund: TemplateDecorator.decorate(capital_commitment.fund),
      fund_units: TemplateDecorator.decorate(fund_units(capital_commitment, start_date, end_date)),

      commitment_adjustments: TemplateDecorator.decorate_collection(adjustments),
      commitment_adjustments_between_dates: TemplateDecorator.decorate_collection(adjustments.where(as_of: start_date..).where(as_of: ..end_date)),
      commitment_adjustments_before_end_date: TemplateDecorator.decorate_collection(adjustments.where(as_of: ..end_date)),

      capital_remittances: TemplateDecorator.decorate_collection(remittances),
      capital_remittances_between_dates: TemplateDecorator.decorate_collection(remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date)),
      capital_remittances_before_end_date: TemplateDecorator.decorate_collection(remittances.where(remittance_date: ..end_date)),

      capital_remittance_payments: TemplateDecorator.decorate_collection(remittance_payments),
      capital_remittance_payments_between_dates: TemplateDecorator.decorate_collection(remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_remittance_payments_before_end_date: TemplateDecorator.decorate_collection(remittance_payments.where(payment_date: ..end_date)),

      remittance_amounts: TemplateDecorator.decorate(remittance_amounts(remittances, fund_currency)),
      remittance_amounts_between_dates: TemplateDecorator.decorate(remittance_amounts(remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date), fund_currency)),
      remittance_amounts_before_end_date: TemplateDecorator.decorate(remittance_amounts(remittances.where(remittance_date: ..end_date), fund_currency)),

      remittance_folio_amounts: TemplateDecorator.decorate(remittance_amounts(remittances, folio_currency)),
      remittance_folio_amounts_between_dates: TemplateDecorator.decorate(remittance_amounts(remittances.where(remittance_date: start_date..).where(remittance_date: ..end_date), folio_currency)),
      remittance_folio_amounts_before_end_date: TemplateDecorator.decorate(remittance_amounts(remittances.where(remittance_date: ..end_date), folio_currency)),

      remittance_payments_amounts: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments, fund_currency)),
      remittance_payments_amounts_between_dates: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date), fund_currency)),
      remittance_payments_amounts_before_end_date: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments.where(payment_date: ..end_date), fund_currency)),

      remittance_payments_folio_amounts: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments, folio_currency)),
      remittance_payments_folio_amounts_between_dates: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments.where(payment_date: start_date..).where(payment_date: ..end_date), folio_currency)),
      remittance_payments_folio_amounts_before_end_date: TemplateDecorator.decorate(remittance_payments_amounts(remittance_payments.where(payment_date: ..end_date), folio_currency)),

      capital_distribution_payments: TemplateDecorator.decorate_collection(distribution_payments),
      capital_distribution_payments_between_dates: TemplateDecorator.decorate_collection(distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date)),
      capital_distribution_payments_before_end_date: TemplateDecorator.decorate_collection(distribution_payments.where(payment_date: ..end_date)),

      distribution_amounts: TemplateDecorator.decorate(distribution_amounts(distribution_payments, fund_currency)),
      distribution_amounts_between_dates: TemplateDecorator.decorate(distribution_amounts(distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date), fund_currency)),
      distribution_amounts_before_end_date: TemplateDecorator.decorate(distribution_amounts(distribution_payments.where(payment_date: ..end_date), fund_currency)),

      distribution_folio_amounts: TemplateDecorator.decorate(distribution_amounts(distribution_payments, folio_currency)),
      distribution_folio_amounts_between_dates: TemplateDecorator.decorate(distribution_amounts(distribution_payments.where(payment_date: start_date..).where(payment_date: ..end_date), folio_currency)),
      distribution_folio_amounts_before_end_date: TemplateDecorator.decorate(distribution_amounts(distribution_payments.where(payment_date: ..end_date), folio_currency)),

      account_entries: TemplateDecorator.new(account_entries),
      account_entries_between_dates: TemplateDecorator.new(account_entries.where(reporting_date: start_date..).where(reporting_date: ..end_date)),
      account_entries_before_end_date: TemplateDecorator.new(account_entries.where(reporting_date: ..end_date)),

      fund_ratios: TemplateDecorator.decorate_collection(fund_ratios),
      fund_ratios_between_dates: TemplateDecorator.decorate_collection(fund_ratios.where(end_date: start_date..).where(end_date: ..end_date)),
      fund_ratios_before_end_date: TemplateDecorator.decorate_collection(fund_ratios.where(end_date: ..end_date)),

      investor_kyc: TemplateDecorator.decorate(capital_commitment.investor_kyc),

      commitment_amount_words: amount_in_words
    }

    @context
  end

  # fund_doc_template_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(capital_commitment, start_date, end_date, fund_doc_template_path)
    template = Sablon.template(File.expand_path(fund_doc_template_path))
    context = prepare_context(capital_commitment, start_date, end_date)

    # add_account_entries(context, capital_commitment, start_date, end_date)
    add_reporting_entries(context, capital_commitment, start_date, end_date)

    generate_custom_fields(context, capital_commitment)

    Rails.logger.debug { "Using context #{context.keys} to render template" }
    Rails.logger.debug "Rendering template"

    file_name = generated_file_name(capital_commitment)
    convert(template, context, file_name)
  end

  def remittance_amounts(remittances, currency)
    call_amount_cents = remittances.sum(:call_amount_cents)
    collected_amount_cents = remittances.sum(:collected_amount_cents)
    committed_amount_cents = remittances.last&.committed_amount_cents || 0
    OpenStruct.new({
                     committed_amount: Money.new(remittances.sum(:committed_amount_cents), currency),
                     call_amount: Money.new(call_amount_cents, currency),
                     collected_amount: Money.new(collected_amount_cents, currency),
                     uncalled_amount: Money.new(committed_amount_cents - call_amount_cents, currency)
                   })
  end

  def remittance_payments_amounts(remittance_payments, currency)
    amount_cents = remittance_payments.sum(:amount_cents)
    folio_amount_cents = remittance_payments.sum(:folio_amount_cents)
    OpenStruct.new({
                     amount: Money.new(amount_cents, currency),
                     folio_amount: Money.new(folio_amount_cents, currency)
                   })
  end

  def distribution_amounts(capital_distribution_payments, currency)
    amount_cents = capital_distribution_payments.sum(:net_payable_cents)
    OpenStruct.new({
                     amount: Money.new(amount_cents, currency)
                   })
  end

  def fund_units(capital_commitment, start_date, end_date)
    transfer_in_amount = Money.new(0)
    transfer_amount = Money.new(0)
    transfer_out_amount = Money.new(0)
    capital_commitment.fund_units.where(issue_date: ..end_date, transfer: %w[out in]).find_each do |fu|
      transfer_amount += fu.amount
      if fu.transfer == "in"
        transfer_in_amount += fu.amount
      else
        transfer_out_amount += fu.amount
      end
    end
    OpenStruct.new({
                     current: capital_commitment.fund_units.sum(:quantity),
                     before_end_date: capital_commitment.fund_units.where(issue_date: ..end_date).sum(:quantity),
                     between_dates: capital_commitment.fund_units.where(issue_date: ..end_date).where(issue_date: start_date..).sum(:quantity),
                     transfer_in_amount:,
                     transfer_out_amount:,
                     transfer_amount:
                   })
  end

  def add_reporting_entries(context, capital_commitment, start_date, end_date)
    raes = capital_commitment.account_entries.where(reporting_date: start_date..end_date, rule_for: "Reporting")
    raes.each do |ae|
      context["reporting_#{ae.template_field_name}"] = TemplateDecorator.decorate(ae)
    end
  end

  def add_account_entries(context, capital_commitment, start_date, end_date)
    context["cumulative_account_entry"] = {}
    capital_commitment.account_entries.pluck(:entry_type).uniq.each do |entry_type|
      context["cumulative_account_entry"][entry_type.delete(' ').underscore] = capital_commitment.cumulative_account_entry(nil, entry_type, start_date, end_date).decorate
    end

    capital_commitment.account_entries.pluck(:name).uniq.each do |name|
      context["cumulative_account_entry"][name.delete(' ').underscore] = capital_commitment.cumulative_account_entry(name, nil, start_date, end_date).decorate
    end
  end

  def generate_custom_fields(context, capital_commitment)
    capital_commitment.properties.each do |k, v|
      context["commitment_#{k}"] = v
    end

    capital_commitment.fund.properties.each do |k, v|
      context["fund_#{k}"] = v
    end

    capital_commitment.investor_kyc.properties.each do |k, v|
      context.store "kyc_#{k}", v
    end
  end
end
