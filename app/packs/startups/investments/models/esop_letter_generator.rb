class EsopLetterGenerator
  include EmailCurrencyHelper
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

  def working_dir_path(holding)
    "tmp/holding_grant_letter_generator/#{rand(1000000)}/#{holding.id}"
  end

  def download_master_grant_letter(holding)
    file = holding.option_pool.grant_letter.download
    file.path
  end

  # master_grant_letter_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(holding, master_grant_letter_path)
    Rails.logger.debug "Generating report"

    odt_file_path = get_odt_file(master_grant_letter_path)

    Rails.logger.debug "Populating template"
    report = ODFReport::Report.new(odt_file_path) do |r|
      Rails.logger.debug "Populating holding fields"
      add_holding_fields(r, holding)
      add_image(r, :employee_signature, holding.user.signature)

      Rails.logger.debug "Populating schedule table"
      r.add_table("Table1", holding.vesting_schedule.each, header: true) do |t|
        t.add_column(:vesting_date) { |item| item[0].strftime('%d/%m/%Y').to_s }
        t.add_column(:vesting_details) { |item| "#{item[2]} Options, can be vested." }
        t.add_column(:vesting_notes) { |item| "This is #{item[1]} % of your Options" }
      end

      Rails.logger.debug "Populating option fields"
      add_option_fields(r, holding)
      add_image(r, :employee_signature, holding.option_pool.certificate_signature)
    end

    report.generate("#{@working_dir}/GrantLetter-#{holding.id}.odt")

    system("libreoffice --headless --convert-to pdf #{@working_dir}/GrantLetter-#{holding.id}.odt --outdir #{@working_dir}")
  end

  def add_holding_fields(report, holding)
    report.add_field :holding_full_name, holding.user.full_name
    report.add_field :holding_investment_instrument, holding.investment_instrument
    report.add_field :holding_employee_id, holding.employee_id
    report.add_field :holding_department, holding.department
    report.add_field :holding_orig_grant_quantity, holding.orig_grant_quantity

    report.add_field :holding_current_quantity, holding.quantity
    report.add_field :holding_grant_date, holding.grant_date
    report.add_field :holding_vested_quantity, holding.vested_quantity
    report.add_field :holding_unvested_quantity, holding.net_unvested_quantity
    report.add_field :holding_excercised_quantity, holding.excercised_quantity
    report.add_field :holding_unexcercised_quantity, holding.net_avail_to_excercise_quantity
    report.add_field :holding_lapsed_quantity, holding.lapsed_quantity

    holding.properties.each do |k, v|
      report.add_field "holding_#{k}", v
    end
  end

  def add_option_fields(report, holding)
    if holding.option_pool
      report.add_field :option_pool_name, holding.option_pool.name
      report.add_field :option_pool_start_date, holding.option_pool.start_date

      holding.option_pool.properties.each do |k, v|
        report.add_field "option_pool_#{k}", v
      end
    end
  end

  def attach(holding)
    holding.grant_letter = File.open("#{@working_dir}/GrantLetter-#{holding.id}.pdf", "rb")
    holding.save
  end
end
