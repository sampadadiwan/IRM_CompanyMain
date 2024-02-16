module FundingRoundsHelper
  def funding_rounds_money(funding_rounds)
    funding_rounds = funding_rounds.group_by(&:name)
    pre_money = funding_rounds.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.pre_money_valuation_cents / 100) }] }
    post_money = funding_rounds.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.post_money_valuation_cents / 100) }] }
    amount_raised = funding_rounds.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_raised_cents / 100) }] }

    data = [
      { name: "Pre Money", data: pre_money },
      { name: "Amount Raised", data: amount_raised },
      { name: "Post Money", data: post_money }
    ]

    column_chart data, library: {
      plotOptions: {
        column: {
          dataLabels: {
            enabled: true,
            format: "<b>{point.y:,.2f}</b>"
          }
        }
      },
      **chart_theme_color
    }
  end
end
