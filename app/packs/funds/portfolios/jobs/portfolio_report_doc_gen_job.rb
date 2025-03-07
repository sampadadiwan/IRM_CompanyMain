class PortfolioReportDocGenJob < DocGenJob
  queue_as :low

  # Returns all the templates from which documents will be generated
  def templates(_model = nil)
    Document.where(id: @document_template_ids)
  end

  # Returns all the KYCs for which documents will be generated
  def models
    if @portfolio_company_id.present?
      Investor.portfolio_companies.where(id: @portfolio_company_id)
    elsif @entity_id.present?
      Investor.portfolio_companies.where("entity_id=?", @entity_id)
    end
  end

  # Validates the KYC before generating the document
  def validate(_portfolio_company)
    [true, ""]
  end

  def generator
    PortfolioReportDocGenerator
  end

  # Validates the inputs before generating the document
  def valid_inputs
    return false unless super

    if @start_date > @end_date
      send_notification("Invalid Dates", @user_id, "danger")
      false
    end
    if @document_template_ids.blank?
      send_notification("Invalid Document Template", @user_id, "danger")
      false
    end
    true
  end

  def cleanup_previous_docs(model, template)
    # model.documents.not_templates.where(name: template.name).find_each(&:destroy)
  end

  def generate_doc_name(model, template, start_date, end_date)
    "#{template.name} #{start_date} to #{end_date} - #{model}"
  end

  # rubocop:disable Metrics/ParameterLists
  def perform(portfolio_report_extract_id, portfolio_company_id, document_template_ids, start_date, end_date,
              user_id, entity_id: nil, options: {})
    # This is the report we want to generate
    @portfolio_report_extract_id = portfolio_report_extract_id

    # These are either all or specific document templates that we want to generate, which are under the portfolio_report
    @document_template_ids = document_template_ids

    # This is the portfolio company for which we want to generate the report, nil if we want to generate for all
    @portfolio_company_id = portfolio_company_id

    @entity_id = entity_id
    @start_date = start_date
    @end_date = end_date
    @user_id = user_id

    options[:portfolio_report_extract_id] = @portfolio_report_extract_id

    Chewy.strategy(:sidekiq) do
      generate(@start_date, @end_date, @user_id, options:) if valid_inputs
    end
  end
  # rubocop:enable Metrics/ParameterLists
end
