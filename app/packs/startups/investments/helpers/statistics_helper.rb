module StatisticsHelper
  def investment_diluted(entity)
    investments = Investment.where(entity_id: entity.id,
                                   investment_instrument: %w[Equity Preferred Options])
                            .joins(:investor).includes(:investor)
    diluted = investments.group_by { |i| i.investor.investor_name }
                         .map { |k, v| [k, v.inject(0) { |sum, e| sum + e.percentage_holding }] }

    pie_chart_with_options diluted
  end

  def investment_undiluted(entity)
    investments = Investment.where(entity_id: entity.id,
                                   investment_instrument: %w[Equity Preferred Options])
                            .joins(:investor).includes(:investor)

    undiluted = investments.group_by { |i| i.investor.investor_name }
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + e.diluted_percentage }] }

    pie_chart_with_options undiluted
  end

  def investment_by_intrument(entity)
    investments = Investment.where(entity_id: entity.id)
                            .group_by(&:investment_instrument)
                            .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_cents / 100) }] }
                            .sort_by { |_k, v| v }.reverse

    column_chart investments, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } },
      **chart_theme_color
    }, prefix: "#{entity.currency}:"
  end

  def funding_rounds_chart(entity)
    column_chart FundingRound.where(entity_id: entity.id).order(id: :asc)
                             .map { |f| ["#{f.name} - #{l(f.created_at.to_date)}", f.amount_raised_cents / 100] },
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}"
                     }
                   } },
                   **chart_theme_color
                 }, decimal: ",", prefix: "#{entity.currency}:"
  end

  def investment_by_investor(entity)
    # We cant use the DB, as values are encrypted
    column_chart Investment.where(entity_id: entity.id)
                           .joins(:investor).includes(:investor).group_by { |i| i.investor.investor_name }
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_cents / 100) }] }
                           .sort_by { |_k, v| v }.reverse,
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}"
                     }
                   } },
                   **chart_theme_color
                 }, decimal: ",", prefix: "#{entity.currency}:"
  end

  def count_by_investor(entity)
    pie_chart Investor.where(entity_id: entity.id)
                      .group("category").count,
              #   xtitle: "Investment Amount",
              #   ytitle: "Type",
              library: {
                plotOptions: {
                  pie: {
                    dataLabels: {
                      enabled: true,
                      format: '{point.name}:<br>{point.percentage:.1f} %'
                    }
                  }
                },
                **chart_theme_color
              },
              donut: true
  end
end
