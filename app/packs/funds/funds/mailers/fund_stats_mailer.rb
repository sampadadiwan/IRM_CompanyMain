class FundStatsMailer < ApplicationMailer
  helper CurrencyHelper
  layout 'stats_mailer'
  def fund_stats_update(support_agent, ctx)
    @support_agent = support_agent
    @ctx = ctx
    mail(to: @support_agent.json_fields["email"], subject: "Fund Stats Update")
  end
end
