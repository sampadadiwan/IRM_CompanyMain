# Tells the fund's Fund accounting users that locked financial statements went back to Draft
# because someone unlocked allocation runs. One delivery per unlock request (FinancialStatementUnlockGuard).
# Worked examples H17, E15 — openspec/changes/fund-financial-statements/design.md#worked-examples
class FinancialStatementNotifier < BaseNotifier
  required_param :entity_id

  def mailer_name(_notification = nil)
    FinancialStatementsMailer
  end

  def email_method(_notification = nil)
    :unlocked_notification
  end

  def email_data(notification)
    {
      notification_id: notification.id,
      user_id: notification.recipient_id,
      entity_id: params[:entity_id],
      fund_id: record.id,
      unlocked_by: params[:unlocked_by],
      period_dates: params[:period_dates]
    }
  end

  notification_methods do
    def message
      "Financial statements for #{record.name} are back to Draft: #{Array(params[:periods]).to_sentence} (allocation runs unlocked by #{params[:unlocked_by]})"
    end

    def url
      financial_statements_path(fund_id: record.id)
    end
  end
end
