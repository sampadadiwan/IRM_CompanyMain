class InvestmentOpportunitySender
  def self.send(investment_opportunity, params, user)
    if params[:notification].present? && InvestmentOpportunity::NOTIFICATION_METHODS.include?(params[:notification])
      investment_opportunity.send(params[:notification])
    elsif params[:custom_notification_id].present?
      investment_opportunity.investors.each do |investor|
        investor.notification_users.each do |user|
          InvestmentOpportunityNotifier.with(record: investment_opportunity, investor_id: investor.id, entity_id: investment_opportunity.entity_id, email_method: params[:email_method], custom_notification_id: params[:custom_notification_id]).deliver_later(user)
        rescue StandardError => e
          msg = "Error sending #{investment_opportunity.name} to #{user.email} #{e.message}"
          Rails.logger.error(msg)
          raise StandardError, msg
        end
      end
    else
      msg = "Invalid Notification for Investment Opportunity #{investment_opportunity.name}"
      Rails.logger.error(msg)
      raise StandardError, msg
    end
  end
end
