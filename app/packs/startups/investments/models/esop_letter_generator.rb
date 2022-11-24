class EsopLetterGenerator
  include EmailCurrencyHelper

  attr_accessor :working_dir

  def initialize(holding, master_grant_letter_path = nil)
    create_working_dir(holding)
    master_grant_letter_path ||= download_master_grant_letter(holding)
    cleanup_old_grant_letter(holding)
    generate(holding, master_grant_letter_path)
    attach(holding)
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
    "tmp/holding_grant_letter_generator/#{holding.id}"
  end

  def create_working_dir(holding)
    @working_dir = working_dir_path(holding)
    FileUtils.mkdir_p @working_dir
  end

  def cleanup
    FileUtils.rm_rf(@working_dir)
  end

  def download_master_grant_letter(holding)
    file = holding.option_pool.grant_letter.download
    file.path
  end

  def get_odt_file(file_path)
    Rails.logger.debug { "Converting #{file_path} to odt" }
    system("libreoffice --headless --convert-to odt #{file_path} --outdir #{@working_dir}")
    "#{@working_dir}/#{File.basename(file_path, '.*')}.odt"
  end

  # master_grant_letter_path sample at "public/sample_uploads/Purchase-Agreement-1.odt"
  def generate(holding, master_grant_letter_path)
    user_signature = nil
    company_signature = nil

    odt_file_path = get_odt_file(master_grant_letter_path)

    report = ODFReport::Report.new(odt_file_path) do |r|
      add_holding_fields(r, holding)
      user_signature = add_image(r, :employee_signature, holding.user.signature)

      add_option_fields(r, holding)
      company_signature = add_image(r, :employee_signature, holding.option_pool.certificate_signature)
    end

    report.generate("#{@working_dir}/GrantLetter-#{holding.id}.odt")

    system("libreoffice --headless --convert-to pdf #{@working_dir}/GrantLetter-#{holding.id}.odt --outdir #{@working_dir}")

    File.delete(user_signature) if user_signature && File.exist?(user_signature)
    File.delete(company_signature) if company_signature && File.exist?(company_signature)
  end

  def add_image(report, field_name, image)
    if image
      file = image.download
      sleep(1)
      report.add_image field_name.to_sym, file.path
      file.path
    end
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
