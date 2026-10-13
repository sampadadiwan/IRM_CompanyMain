# Internal evergreen alerts to named roles (approvers, relationship manager, FundOps / FundAccounting /
# Compliance tags) — in-app and email, fixed wording. Who gets each alert is decided by EvergreenAlerts.
# open-ended-funds § Notifications
class EvergreenOpsNotifier < BaseNotifier
  required_param :email_method, :entity_id

  def mailer_name(_notification = nil)
    EvergreenOpsMailer
  end

  def email_data(notification)
    { notification_id: notification.id, user_id: notification.recipient_id, entity_id: params[:entity_id],
      record_type: record.class.name, record_id: record.id, fund_id: record.fund_id, pct: params[:pct] }
  end

  notification_methods do
    def message
      EvergreenOpsMailer.title(params[:email_method], record, pct: params[:pct])
    end

    def url
      EvergreenOpsMailer.link(record)
    end
  end
end
