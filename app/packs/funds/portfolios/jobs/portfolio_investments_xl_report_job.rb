class PortfolioInvestmentsXlReportJob < ApplicationJob
  include Rails.application.routes.url_helpers
  queue_as :default

  def perform(as_of, user_id, portfolio_company_id: nil, fund_id: nil)  
    Chewy.strategy(:sidekiq) do
      generate(as_of, user_id, portfolio_company_id:, fund_id:)
    end
  end

  # rubocop:disable Rails/OutputSafety
  def generate(as_of, user_id, portfolio_company_id: nil, fund_id: nil)
    user = User.find(user_id)
    entity = user.entity
    as_of = Date.parse(as_of)

    aggregate_portfolio_investments = entity.aggregate_portfolio_investments
    if portfolio_company_id.present?
      portfolio_company = Investor.find(portfolio_company_id)
      aggregate_portfolio_investments = portfolio_company.aggregate_portfolio_investments
    end

    if fund_id.present?
      fund = Fund.find(fund_id)
      aggregate_portfolio_investments = fund.aggregate_portfolio_investments
    end

    send_notification("Generating Portfolio Investment Report", user_id)

    # Generate the report
    file_name = "tmp/portfolio_investments_#{as_of.strftime('%m_%y')}.xlsx"
    PortfolioInvestmentAsOfReport.new(aggregate_portfolio_investments, user, as_of:).save_to_file(file_name)
    send_notification("Portfolio Investment Report created", user_id)

    # Save it as a document
    if portfolio_company_id.present?
      report_doc = portfolio_company.documents.build(name: "Portfolio Investments Report - #{portfolio_company.investor_name} - #{as_of}", user_id: user_id, entity_id: portfolio_company.entity_id, orignal: true, owner_tag: "Generated")
    elsif fund_id.present?
      report_doc = fund.documents.build(name: "Portfolio Investments Report - #{fund.name} - #{as_of}", user_id: user_id, entity_id: fund.entity_id, orignal: true, owner_tag: "Generated")
    else
      folder = entity.root_folder.children.where(name: "tmp").first
      folder ||= entity.root_folder.children.create!(name: "tmp", entity_id: entity.id)
      report_doc = folder.documents.build(name: "Portfolio Investments Report - All - #{as_of}", user_id: user_id, entity_id: entity.id, orignal: true, owner_tag: "Generated", folder: folder)
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
