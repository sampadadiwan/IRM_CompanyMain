class XlReportJob < ApplicationJob
  queue_as :serial
  sidekiq_options retry: 2
  # user_id - The id of the user who is requesting the docs generation
  # fund_id - The id of the fund for which we want to generate docs for all capital_commitments.
  def perform(fund_id, user_id = nil)
    Chewy.strategy(:sidekiq) do
      # Find the fund
      fund = Fund.find(fund_id)
      # Find the templates in the reports folder
      fund.reports_folder.documents.templates.each do |template|
        if template.uploaded_file_extension == "xlsx"
          FundXl.new.merge_data(fund, template, user_id)
          UserAlert.new(user_id:, message: "#{template.name} creation completed", level: "success").broadcast
        else
          UserAlert.new(user_id:, message: "Skipping #{template.name}, it is not an excel file", level: "error").broadcast
        end
      end
      # Update the user with the completion message
      UserAlert.new(user_id:, message: "Fund Report creation completed", level: "info").broadcast
    end
  end
end
