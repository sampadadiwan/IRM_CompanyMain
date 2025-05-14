class GenerateCrisilReport < Trailblazer::Operation
  step :create_file_and_copy_template
  step :generate_report
  step :save_and_upload_report
  left :handle_errors, Output(:failure) => End(:failure)
  step :notify

  # Copy the template report to the temp file path
  # This temp file will be attached to a Document object later
  def create_file_and_copy_template(ctx, fund_id:, report_name:, excel:, **)
    return true unless excel || report_name.delete(" ").casecmp?("CRISILReport")

    ctx[:file_path] = create_file_path(report_name, fund_id)
    template_path = report_name.delete(" ").casecmp?("CRISILReport") ? "sample_uploads/CRISIL Report.xlsx" : "sample_uploads/#{report_name}.xlsx"
    copy_template(template_path, ctx[:file_path])
    true
  end

  # Can generate excel report for all funds of the entity or for a single fund
  # Can generate UI reports for a single fund
  # rubocop:disable Metrics/ParameterLists
  def generate_report(ctx, fund_id:, report_name:, start_date:, end_date:, excel:, single:, **)
    # Generate excel report if excel is true
    if excel
      generate_partial_report(ctx, fund_id, report_name, start_date, end_date, single: single)
    # Generate full excel report if report_name is CRISILReport
    # The full crisil report can only be an excel report
    elsif report_name.delete(" ").casecmp?("CRISILReport")
      generate_full_report(ctx, fund_id, start_date, end_date)
    # generate Report object which is shown on the UI, for a single fund
    else
      reporter = "#{report_name}Job".constantize.new
      reporter.generate_report(fund_id, start_date, end_date)
    end
  end

  def generate_full_report(ctx, fund_id, start_date, end_date)
    workbook = RubyXL::Parser.parse(ctx[:file_path])

    CrisilReportJob::ALL_REPORT_JOBS.each do |report_name|
      Rails.logger.info { "Running #{report_name}Job for fund #{fund_id}" }
      workbook = run_xl_report_job(fund_id, report_name, start_date, end_date, workbook)
    end
    workbook.save
    ctx[:report_name] = "CRISIL Report"
  end

  def generate_partial_report(fund_id, report_name, start_date, end_date, single: false)
    # Copy the template report to the temp file path
    # This temp file will be attached to a Document object later
    workbook = RubyXL::Parser.parse(ctx[:file_path])

    workbook = run_xl_report_job(fund_id, report_name, start_date, end_date, workbook, single: single)
    workbook.save
    report_name += "(All Funds)" unless single
    ctx[:report_name] = report_name
  end

  def run_xl_report_job(fund_id, report_name, start_date, end_date, workbook = nil, single: false)
    reporter = "#{report_name}Job".constantize.new
    reporter.generate_excel_report(fund_id, start_date, end_date, workbook, single: single)
  end

  def create_file_path(report_name, fund_id)
    Rails.root.join("tmp/#{report_name}_#{fund_id}_#{Time.zone.now}.xlsx")
  end

  def copy_template(template_path, file_path)
    FileUtils.cp(Rails.public_path.join(template_path), file_path)
  end

  def report_folder(fund)
    fund.document_folder.children.where(name: "Reports").first
  end

  def save_and_upload_report(ctx, fund_id:, user_id:, report_name:, start_date:, end_date:, excel:, **)
    return unless excel || report_name.delete(" ").casecmp?("CRISILReport")

    fund = Fund.find(fund_id)

    file = File.open(ctx[:file_path])
    report_name = "#{report_name} #{start_date.strftime('%d %B,%Y')} to #{end_date.strftime('%d %B,%Y')}"

    ActiveRecord::Base.transaction do
      # Delete all old reports with the same name - basically the reports of the same type that were generated for the same time period
      Document.where(name: report_name, entity_id: fund.entity_id).destroy_all if Document.exists?(name: report_name, entity_id: fund.entity_id)
      # Create a new Docment with the new report excel file
      Document.create!(entity_id: fund.entity_id, owner: fund, name: report_name, file:, folder: report_folder(fund), user: User.find(user_id), orignal: true, download: true)
    end
  rescue StandardError => e
    ctx[:errors] = e.message
    false
  end

  def notify(_ctx, report_name:, user_id:, **)
    UserAlert.new(user_id:, message: "#{report_name} generation completed.", level: "success").broadcast
  end

  def handle_errors(ctx, report_name:, user_id:, **)
    UserAlert.new(message: "#{report_name} Generation Failed: #{ctx[:errors]}", user_id:, level: "danger").broadcastif user_id.present?
    false
  end
  # rubocop:enable Metrics/ParameterLists
end
