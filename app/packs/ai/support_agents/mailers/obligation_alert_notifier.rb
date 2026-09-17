# Consolidated side letter obligation alert (one per recipient per enforcement
# run). record: the SideLetterObligationAgent's SupportAgent; params[:items]:
# serialized obligation/task rows (see ObligationEnforcement#serialize).
class ObligationAlertNotifier < BaseNotifier
  required_param :entity_id
  required_param :items

  def mailer_name(_notification = nil)
    SideLetterObligationMailer
  end

  def email_method(_notification = nil)
    :obligation_reminder
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      support_agent_id: record&.id,
      entity_id: params[:entity_id],
      items: params[:items]
    }
  end

  notification_methods do
    def message
      counts = Array(params[:items]).group_by { |i| i["kind"] }.transform_values(&:count)
      "Side letter obligations: #{counts.map { |k, v| "#{v} #{k}" }.join(', ')}"
    end

    # nil => BaseNotifier's email gate passes and the mailer's own template is
    # used (no per-entity CustomNotification required for these alerts)
    def custom_notification
      nil
    end

    def url
      support_agent_path(id: record.id, sub_domain: record.entity.sub_domain)
    end
  end
end
