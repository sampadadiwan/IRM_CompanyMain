class PortfolioInvestmentsXlReportJob < ApplicationJob
  include Rails.application.routes.url_helpers
  queue_as :default

  def perform(as_of, user_id, portfolio_company_id: nil, fund_id: nil)
    Chewy.strategy(:sidekiq) do
      generate(as_of, user_id, portfolio_company_id:, fund_id:)
    end
  end

  # Get the reports folder under the entity or fund or portfolio_company
  # Ensure the reports folder is created with the owner set to nil
  def get_reports_folder(model)
    entity = model.respond_to?(:entity) ? model.entity : model
    reports_folder = model.document_folder.children.where(name: "Reports", entity:, private: true).first
    reports_folder ||= model.document_folder.children.create!(name: "Reports", entity:, private: true)
    reports_folder
  end

  # rubocop:disable Rails/OutputSafety
  def generate(as_of, user_id, portfolio_company_id: nil, fund_id: nil)
    user = User.find(user_id)
    entity = user.entity
    currency = entity.currency
    as_of = Date.parse(as_of)

    aggregate_portfolio_investments = entity.aggregate_portfolio_investments
    if portfolio_company_id.present?
      portfolio_company = Investor.find(portfolio_company_id)
      aggregate_portfolio_investments = portfolio_company.aggregate_portfolio_investments
    end

    if fund_id.present?
      fund = Fund.find(fund_id)
      currency = fund.currency
      aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    end

    send_notification("Generating Portfolio Investment Report", user_id)

    # Generate the report
    file_name = "tmp/portfolio_investments_#{as_of.strftime('%m_%y')}.xlsx"
    PortfolioInvestmentAsOfReport.new(aggregate_portfolio_investments, user, as_of:, currency:).save_to_file(file_name)
    send_notification("Portfolio Investment Report created", user_id)

    # Save it as a document
    if portfolio_company_id.present?
      # Get the reports folder under the fund
      reports_folder = get_reports_folder(portfolio_company)
      report_doc = portfolio_company.documents.build(name: "Portfolio Investments Report - #{portfolio_company.investor_name} - #{as_of}", user_id: user_id, entity_id: portfolio_company.entity_id, orignal: true, owner_tag: "Generated", folder: reports_folder)
    elsif fund_id.present?
      # Get the reports folder under the fund
      reports_folder = get_reports_folder(fund)
      report_doc = fund.documents.build(name: "Portfolio Investments Report - #{fund.name} - #{as_of}", user_id: user_id, entity_id: fund.entity_id, orignal: true, owner_tag: "Generated", folder: reports_folder)
    else
      # Get the reports folder under the entity
      reports_folder = get_reports_folder(entity)
      report_doc = folder.documents.build(name: "Portfolio Investments Report - All - #{as_of}", user_id: user_id, entity_id: entity.id, orignal: true, owner_tag: "Generated", folder: reports_folder)
    end

    report_doc.file = File.open(file_name, "rb")
    report_doc.save!

    # Send the report to the user
    DocumentNotifier.with(record: report_doc,
                          entity_id: report_doc.entity_id,
                          email_method: "send_document").deliver(user)

    send_notification("Portfolio Investment Report sent via email. #{ActionController::Base.helpers.link_to('Click to view Report', document_url(report_doc.id))}".html_safe, user_id)
  end
  # rubocop:enable Rails/OutputSafety
end
