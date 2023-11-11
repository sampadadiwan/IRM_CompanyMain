module FundsHelper
  def fund_bread_crumbs(current = nil)
    @bread_crumbs = { Funds: funds_path }
    @bread_crumbs[Fund.find(params[:fund_id]).name] = fund_path(params[:fund_id]) if params[:fund_id]
    @bread_crumbs[current] = nil if current
  end

  def investor_commitments_chart(capital_commitments)
    commitments = capital_commitments.joins(:fund, :investor)
                                     .order(commitment_date: :asc)
                                     .group_by { |v| v.fund.name }
                                     .map { |fname, vals| [fname, vals.inject(0) { |sum, com| sum + com.committed_amount.to_f }] }

    column_chart cumulative(commitments), library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } }
    }
  end
end
