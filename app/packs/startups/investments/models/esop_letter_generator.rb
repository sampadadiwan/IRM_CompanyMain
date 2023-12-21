class EsopLetterGenerator
  include CurrencyHelper
  include DocumentGeneratorBase

  attr_accessor :working_dir

  def initialize(holding, master_grant_letter_path = nil)
    if holding.option_pool.grant_letter.present?
      create_working_dir(holding)
      master_grant_letter_path ||= download_master_grant_letter(holding)
      cleanup_old_grant_letter(holding)
      generate(holding, master_grant_letter_path)
      attach(holding)
    else
      raise "EsopLetterGenerator: No Grant letter template found for option_pool #{holding.option_pool.id} "
    end
  ensure
    cleanup
  end

  private

  def cleanup_old_grant_letter(holding)
    if holding.grant_letter
      holding.grant_letter = nil
      holding.save
    end
  end

  def download_master_grant_letter(holding)
    file = holding.option_pool.grant_letter.download
    file.path
  end

  # master_grant_letter_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(holding, master_grant_letter_path)
    Rails.logger.debug "Generating report"

    template = Sablon.template(File.expand_path(master_grant_letter_path))
    context = { vesting_schedules: holding.vesting_schedule }
    Rails.logger.debug "Populating template"
    Rails.logger.debug "Populating holding fields"
    add_holding_fields(context, holding)
    add_image(context, :employee_signature, holding.user.signature)

    add_option_fields(context, holding)
    add_image(context, :employee_signature, holding.option_pool.certificate_signature)

    Rails.logger.debug { "Rendering with context #{context}" }
    file_name = "#{@working_dir}/Holding-#{holding.id}"
    convert(template, context, file_name)
  end

  def add_holding_fields(context, holding)
    context.store  :holding_full_name, holding.user.full_name
    context.store  :holding_investment_instrument, holding.investment_instrument
    context.store  :holding_employee_id, holding.employee_id
    context.store  :holding_department, holding.department
    context.store  :holding_orig_grant_quantity, holding.orig_grant_quantity

    context.store  :holding_current_quantity, holding.quantity
    context.store  :holding_grant_date, holding.grant_date
    context.store  :holding_vested_quantity, holding.vested_quantity
    context.store  :holding_unvested_quantity, holding.net_unvested_quantity
    context.store  :holding_excercised_quantity, holding.excercised_quantity
    context.store  :holding_unexcercised_quantity, holding.net_avail_to_excercise_quantity
    context.store  :holding_lapsed_quantity, holding.lapsed_quantity

    holding.properties.each do |k, v|
      context.store  "holding_#{k}", v
    end
  end

  def add_option_fields(context, holding)
    if holding.option_pool
      context.store  :option_pool_name, holding.option_pool.name
      context.store  :option_pool_start_date, holding.option_pool.start_date

      holding.option_pool.properties.each do |k, v|
        context.store "option_pool_#{k}", v
      end
    end
  end

  def attach(holding)
    holding.grant_letter = File.open("#{@working_dir}/GrantLetter-#{holding.id}.pdf", "rb")
    holding.save
  end
end
