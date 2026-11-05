# ⑨ One Noticed event for every internal compliance notice (assignment, approval request, decision,
# escalation, run failed, version notices, digest). `record` is the RECIPIENT user, as in
# WeeklyTaskDigestNotifier, so the in-app bell row belongs to them and email gating works.
# Never sent to investors or advisors — recipients come only from ComplianceNotices (X35).
class ComplianceNotifier < BaseNotifier
  required_param :entity_id
  required_param :kind

  def mailer_name(_notification = nil)
    ComplianceMailer
  end

  def email_method(_notification = nil)
    params[:kind].to_s == "digest" ? :digest : :notice
  end

  def email_data(notification)
    { notification_id: notification.id, user_id: notification.recipient_id, entity_id: params[:entity_id],
      kind: params[:kind], message: params[:message], lines: params[:lines], as_of: params[:as_of] }
  end

  notification_methods do
    def message
      params[:message]
    end

    # Internal notice: no CustomNotification, keeps the email condition true (see WeeklyTaskDigestNotifier)
    def custom_notification
      nil
    end

    def url
      compliance_home_path
    end
  end
end
