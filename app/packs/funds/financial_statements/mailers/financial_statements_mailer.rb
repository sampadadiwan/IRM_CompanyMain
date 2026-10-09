# Emails for fund financial statements. Dates in the body render "Mon dd, yyyy" via
# EmailDateLocalization (bare l(date) in the view).
class FinancialStatementsMailer < ApplicationMailer
  # Locked statements were returned to Draft by an allocation run unlock (FinancialStatementNotifier)
  def unlocked_notification
    @fund = Fund.find(params[:fund_id])
    @period_dates = Array(params[:period_dates]).map { |from, to| [Date.parse(from), Date.parse(to)] }
    @unlocked_by = params[:unlocked_by]
    send_mail(subject: "#{@fund.name}: financial statements back to Draft after an allocation unlock")
  end
end
