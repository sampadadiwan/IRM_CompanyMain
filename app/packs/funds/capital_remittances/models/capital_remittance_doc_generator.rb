class CapitalRemittanceDocGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir, :fund_doc_template_name

  # capital_remittance - we want to generate the document for this remittance
  # fund document template - the document are we using as  template for generation
  def initialize(capital_remittance, fund_doc_template, start_date, end_date, user_id, options: nil)
    Rails.logger.debug { "CapitalRemittanceDocGenerator #{capital_remittance.id},  #{fund_doc_template.name}, #{start_date}, #{end_date}, #{user_id}, #{options} " }

    @fund_doc_template_name = fund_doc_template.name

    fund_doc_template.file.download do |tempfile|
      fund_doc_template_path = tempfile.path
      create_working_dir(capital_remittance)
      generate(capital_remittance, fund_doc_template_path)
      upload(fund_doc_template, capital_remittance)
      notify(fund_doc_template, capital_remittance, user_id) if user_id
    ensure
      cleanup
    end
  end

  private

  def working_dir_path(capital_remittance)
    "tmp/fund_doc_generator/capital_remittance/#{rand(1_000_000)}/#{capital_remittance.id}"
  end

  def notify(fund_doc_template, capital_remittance, user_id)
    UserAlert.new(user_id:, message: "Document #{fund_doc_template.name} generated for #{capital_remittance.investor_name}. Please refresh the page.", level: "success").broadcast
  end

  def generate(capital_remittance, fund_doc_template_path)
    template = Sablon.template(File.expand_path(fund_doc_template_path))

    context = {}

    context.store :date, Time.zone.today.strftime("%d %B %Y")

    context.store :entity, capital_remittance.entity
    context.store :fund, TemplateDecorator.decorate(capital_remittance.fund)
    context.store :capital_remittance, CapitalRemittanceTemplateDecorator.decorate(capital_remittance)
    context.store :investor_kyc, TemplateDecorator.decorate(capital_remittance.capital_commitment.investor_kyc)
    context.store :capital_call, TemplateDecorator.decorate(capital_remittance.capital_call)

    context.store :due_date, capital_remittance.capital_call.due_date&.strftime("%d %B %Y")
    context.store :call_date, capital_remittance.capital_call.call_date&.strftime("%d %B %Y")

    context.store :capital_commitment, CapitalCommitmentCallNoticeTemplateDecorator.decorate(capital_remittance.capital_commitment)
    context.store :fund_unit_setting, TemplateDecorator.decorate(capital_remittance.capital_commitment.fund_unit_setting)

    # add_amounts(capital_remittance, context)

    file_name = generated_file_name(capital_remittance)
    convert(template, context, file_name)
  end

  # Dead code
  def add_amounts(capital_remittance, context)
    call_amount_in_words = capital_remittance.fund.currency == "INR" ? capital_remittance.call_amount.to_i.rupees.humanize : capital_remittance.call_amount.to_i.to_words.humanize

    context.store  :call_amount_words, call_amount_in_words
    context.store  :call_amount, money_to_currency(capital_remittance.call_amount)
    context.store  :call_amount_in_words, (capital_remittance.fund.currency == "INR" ? capital_remittance.call_amount.to_i.rupees.humanize : capital_remittance.call_amount.to_i.to_words.humanize)

    context.store  :committed_amount, money_to_currency(capital_remittance.capital_commitment.committed_amount)

    collected_amount_in_words = capital_remittance.fund.currency == "INR" ? capital_remittance.collected_amount.to_i.rupees.humanize : capital_remittance.collected_amount.to_i.to_words.humanize

    context.store  :collected_amount_words, collected_amount_in_words
    context.store  :collected_amount, money_to_currency(capital_remittance.collected_amount)
    context.store  :due_amount, money_to_currency(capital_remittance.due_amount)
    context.store  :due_amount_in_words, (capital_remittance.fund.currency == "INR" ? capital_remittance.due_amount.to_i.rupees.humanize : capital_remittance.due_amount.to_i.to_words.humanize)

    context.store  :capital_fee, money_to_currency(capital_remittance.capital_fee)
    context.store  :other_fee, money_to_currency(capital_remittance.other_fee)
  end
end
