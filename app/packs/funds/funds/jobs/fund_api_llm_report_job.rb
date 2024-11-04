class FundApiLlmReportJob < ApplicationJob
  queue_as :low

  def perform(fund_id, user_id, report_template_name: "Report Template")
    Chewy.strategy(:sidekiq) do
      # fetch the AggregatePortfolioInvestments for this fund
      fund = Fund.find(fund_id)
      apis = fund.aggregate_portfolio_investments
      apis.each do |api|
        # Get the latest folder created for this api
        latest_api_folder = api.document_folder.children.order(created_at: :desc).first
        if latest_api_folder.present?
          FolderLlmReportJob.perform_now(latest_api_folder.id, user_id, "AggregatePortfolioInvestment", report_template_name:)
        else
          Rails.logger.debug { "No folder found for api: #{api.id}" }
        end
      end
    end
  end
end
