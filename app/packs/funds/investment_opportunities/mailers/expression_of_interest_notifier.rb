class ExpressionOfInterestNotifier < BaseNotifier
  def mailer_name(_notification = nil)
    ExpressionOfInterestMailer
  end

  def email_method(_notification = nil)
    :notify_approved
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      expression_of_interest_id: record.id,
      investor_id: record.investor_id,
      investor_advisor_id: investor_advisor_id(record.investor.investor_entity_id, notification.recipient_id)
    }
  end

  notification_methods do
    def message
      @expression_of_interest = record
      params[:msg] || "Expression Of Interest Approved: #{@expression_of_interest&.investment_opportunity&.company_name}"
    end

    def custom_notification
      nil
    end

    def url
      expression_of_interest_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
