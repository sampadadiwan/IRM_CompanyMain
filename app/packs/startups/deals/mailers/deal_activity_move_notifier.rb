class DealActivityMoveNotifier < BaseNotifier
  # Triggered when a deal moves to a new activity/stage.
  # It looks up a CustomNotification owned by the Deal with email_method 'deal_activity_move'.

  def mailer_name(_notification = nil)
    # Both standard and custom move notifications use DealMailer.
    # Custom templates will call ApplicationMailer#adhoc_notification (inherited).
    DealMailer
  end

  def email_method(_notification = nil)
    # If a custom notification exists, this will trigger ApplicationMailer#adhoc_notification
    # otherwise it will use the default subject/body provided by the notifier.
    custom_notification ? :adhoc_notification : :deal_activity_move
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      record_id: record.id,
      record_type: record.class.name,
      investor_id: record.investor_id,
      deal_id: record.deal_id,
      custom_notification_id: custom_notification&.id
    }
  end

  # Find the custom notification template for this deal and transition
  def custom_notification
    # Prioritize a template tagged with the activity title, fall back to a generic move notification for the deal
    @custom_notification ||= record.deal.custom_notifications.enabled
                                   .where(email_method: "deal_activity_move")
                                   .find_by(tag: params[:activity_title]) ||
                             record.deal.custom_notifications.enabled
                                   .find_by(email_method: "deal_activity_move", tag: [nil, ""])
  end

  notification_methods do
    def message
      "Deal #{record.deal.name} for #{record.investor_name} has moved to stage: #{params[:activity_title]}"
    end

    def url
      deal_investor_url(record, sub_domain: record.deal.entity.sub_domain)
    end
  end
end
