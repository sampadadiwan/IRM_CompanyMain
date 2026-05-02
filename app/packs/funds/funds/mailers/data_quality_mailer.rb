class DataQualityMailer < ApplicationMailer
  def quality_report(support_agent, fund, ctx)
    @support_agent = support_agent
    @fund          = fund
    @check_results = ctx[:check_results]
    @issues        = ctx[:issues]
    @health_score  = ctx[:health_score]

    to = support_agent.json_fields["email"].presence ||
         fund.entity.employees.active.pluck(:email).join(",")

    mail(to:, subject: "Data Quality Report — #{fund.name} (#{@health_score}%)")
  end
end
