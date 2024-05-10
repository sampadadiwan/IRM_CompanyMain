class FundDocGenJob < ApplicationJob
  queue_as :doc_gen
  sidekiq_options retry: 1

  def perform(fund_id, start_date, end_date, user_id: nil)
    error_msg = []

    if start_date > end_date
      send_notification("Invalid Dates", user_id, "danger")
    else

      # Find the fund
      fund = Fund.find(fund_id)
      # Find the template with owner_tag "Fund Template"
      templates = fund.documents.templates.where(owner_tag: "Fund Template")
      Chewy.strategy(:sidekiq) do
        # Loop through each fund and generate the documents
        templates.each do |document_template|
          send_notification("Generating #{document_template.name} for #{fund.name}", user_id)
          FundDocGenerator.new(fund, document_template, start_date, end_date, user_id)
        rescue Exception => e
          msg = "Error generating #{document_template.name} for #{fund.name} #{e.message}"
          send_notification(msg, user_id, "danger")
          error_msg << { msg:, kyc: fund }
        end
      end

      # Send email if there are any errors
      if error_msg.present?
        send_notification("Documentation generation completed with #{error_msg.length} errors. Errors will be sent via email", user_id, :danger)
        EntityMailer.with(entity_id: User.find(user_id).entity_id, user_id:, error_msg:).doc_gen_errors.deliver_now
      end

      send_notification("No templates found for #{fund.name}", user_id, "danger") if templates.blank?

    end
  end
end
