class FundStatsMailer < SupportAgentBaseMailer
  def fund_stats_update(support_agent, ctx)
    @support_agent = support_agent
    @ctx = ctx
    @entity = support_agent.entity
    @currency = ctx[:funds]&.first&.currency || "INR"

    to = support_agent.json_fields["email"].presence ||
         @entity.employees.active.pluck(:email).join(",")

    mail(to:, subject: "Fund Stats Update — #{@entity.name}")
  end
end
