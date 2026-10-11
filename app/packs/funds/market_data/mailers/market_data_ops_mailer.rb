# Mails for MarketDataOpsNotifier. Subject dates use the email format with locale :en forced.
# X6, X7, E14 — openspec/changes/fund-market-data/business-rules.md
class MarketDataOpsMailer < ApplicationMailer
  def fx_feed_missing
    @run = MarketDataRun.find(params[:record_id])
    send_mail(subject: "FX feed: no rates loaded for #{I18n.l(@run.run_date, format: :email, locale: :en)}")
  end

  # H10 — a new suggested corporate action
  def corporate_action_suggested
    @suggestion = CorporateActionSuggestion.find(params[:record_id])
    send_mail(subject: "Suggested corporate action: #{@suggestion.investment_instrument.name} — #{@suggestion.subject}")
  end

  # E57 — a contract expires in 5 business days
  def derivative_expiring
    @contract = DerivativeContract.find(params[:record_id])
    send_mail(subject: "#{@contract.name} expires on #{I18n.l(@contract.expiry_date, format: :email, locale: :en)}")
  end

  def prices_feed_missing
    @run = MarketDataRun.find(params[:record_id])
    send_mail(subject: "Price feed: no prices loaded for #{I18n.l(@run.run_date, format: :email, locale: :en)}")
  end
end
