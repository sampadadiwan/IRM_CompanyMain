# frozen_string_literal: true

# ⑦ One Noticed event per maker–checker notice — approval requested, approval withdrawn, maker–checker turned off
# (OWASP review 2026-11 M13, design card ⑦ "Notifications"). `record` is the RECIPIENT user, as in ComplianceNotifier,
# so the bell row belongs to them and the email gate works. Recipients come only from MakerCheckerNotices.
# Internal notices: no CustomNotification, the firm can't mute them (design "Notifications": Customisable = No).
class MakerCheckerNotifier < BaseNotifier
  required_param :entity_id
  required_param :kind

  def mailer_name(_notification = nil)
    MakerCheckerMailer
  end

  def email_method(_notification = nil)
    :notice
  end

  def email_data(notification)
    { notification_id: notification.id, user_id: notification.recipient_id, entity_id: params[:entity_id],
      kind: params[:kind], message: params[:message], approvable_type: params[:approvable_type],
      approvable_id: params[:approvable_id], actor_id: params[:actor_id] }
  end

  notification_methods do
    # The bell: the same sentence as the email subject
    def message
      params[:message]
    end

    # Internal notice: no CustomNotification, keeps the email condition true (as ComplianceNotifier)
    def custom_notification
      nil
    end

    # H19 — the bell opens the call / distribution; the switch-off notice opens the firm's settings
    def url
      case params[:approvable_type]
      when "CapitalCall" then capital_call_path(params[:approvable_id])
      when "CapitalDistribution" then capital_distribution_path(params[:approvable_id])
      else entity_path(params[:entity_id])
      end
    end
  end
end
