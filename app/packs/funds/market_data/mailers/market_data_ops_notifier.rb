# Internal market-data alerts to the entity's Fund accounting users (fixed wording, not
# customisable): feed runs that could not load everything. One notification per run date
# (MarketDataRun#notified_at). openspec/changes/fund-market-data — design › Notifications.
class MarketDataOpsNotifier < BaseNotifier
  required_param :entity_id, :email_method

  def mailer_name(_notification = nil)
    MarketDataOpsMailer
  end

  def email_method(_notification = nil)
    params[:email_method].to_sym
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      record_id: record.id
    }
  end

  notification_methods do
    def message
      case params[:email_method].to_s
      when "corporate_action_suggested"
        "Suggested corporate action for #{record.investment_instrument.name}: #{record.subject} (ex-date #{I18n.l(record.ex_date)})"
      when "derivative_expiring"
        "#{record.name} expires on #{I18n.l(record.expiry_date)}"
      when "fx_feed_missing"
        "FX feed: no rates loaded for #{I18n.l(record.run_date)} (#{record.missing_items.size} missing)"
      else
        "Price feed: no prices loaded for #{I18n.l(record.run_date)} (#{record.missing_items.size} missing)"
      end
    end

    def url
      case params[:email_method].to_s
      when "corporate_action_suggested" then corporate_action_suggestions_path
      when "derivative_expiring" then derivative_contract_path(id: record.id)
      else market_data_runs_path
      end
    end
  end
end
