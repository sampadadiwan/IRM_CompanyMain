class FundLlmReportJob < ApplicationJob
  queue_as :low

  def perform(fund_id, user_id, report_type,
              report_template_name: "Report Template",
              include_kpis: false, include_apis: false,
              start_date: nil, end_date: nil)
    Chewy.strategy(:sidekiq) do
      # Get the fund
      fund = Fund.find(fund_id)

      case report_type
      when "KpiReport"
        kpi_reports(fund, user_id, report_template_name, include_kpis:, include_apis:, start_date:, end_date:)
      else
        Rails.logger.debug { "Unknown report type: #{report_type}" }
        raise "Unknown report type: #{report_type}"
      end
    rescue StandardError => e
      Rails.logger.debug e.backtrace
      Rails.logger.debug { "Failed to generate report: #{e.message}" }
      send_notification("Failed to generate report: #{e.message}", user_id)
    end
  end

  def kpi_reports(fund, user_id, report_template_name, include_kpis: false, include_apis: false, start_date: nil, end_date: nil)

    # Get the kpi for this api which are within the date range
    kpi_reports = fund.entity.kpi_reports.where(as_of: start_date..end_date).order(as_of: :desc)

    if kpi_reports.present?

      kpi_reports.each do |kpi_report|
        # Get the output folder for this report
        output_folder_name = "KpiReport-#{kpi_report.as_of.strftime('%Y-%m-%d')}"
        output_folder_id = get_output_folder(fund, output_folder_name).id

        # Check if we need to include the KPIs
        kpis = include_kpis ? to_json(kpi_report.kpis) : nil
        # Check if we need to include the APIs
        apis = include_apis ? to_json(fund.aggregate_portfolio_investments.where(portfolio_company_id: kpi_report.portfolio_company_id)) : nil
        # Get the folder for this kpi report, which has the documents, and generate a report
        if kpi_report.document_folder_id.present?
          FolderLlmReportJob.perform_now(kpi_report.document_folder_id, user_id,
                                         report_template_name:, kpis:, apis:, output_folder_id:, output_file_name_prefix: kpi_report.portfolio_company.investor_name)
        end
      end

    else
      msg = "Generate Report: No KPI reports found for portfolio company: #{api.portfolio_company.investor_name}"
      Rails.logger.debug { msg }
      send_notification(msg, user_id)
    end
  end


  def get_output_folder(fund, folder_name)
    # Get the folder called Portfolio Company Reports under the fund
    pcr_folder = fund.document_folder.children.find_by(name: "Portfolio Company Reports")
    pcr_folder = fund.document_folder.children.create(name: "Portfolio Company Reports", entity_id: fund.entity_id, owner: fund) if pcr_folder.nil?

    # Get the folder for the end date
    folder = pcr_folder.children.find_by(name: folder_name)
    folder = pcr_folder.children.create(name: folder_name, entity_id: fund.entity_id, owner: fund) if folder.nil?

    folder
  end

  # This is to use the jbuilder template to produce json
  def to_json(models)
    if models&.length&.positive?
      model = models[0]
      renderer = ApplicationController.renderer.new
      renderer.render(template: "#{model.class.name.underscore.pluralize}/index", formats: [:json], assigns: { "#{model.class.name.underscore.pluralize}": models })

    end
  end
end
