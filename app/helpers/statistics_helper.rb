module StatisticsHelper
  def pie_chart_with_options(data)
    pie_chart data, library: { plotOptions: { pie: {
      dataLabels: {
        enabled: true,
        format: '{point.name}:<br>{point.percentage:.1f} %'
      }
    } } },
                    #  stacked: false,
                    decimal: ",",
                    prefix: "%"
  end

  def investment_diluted(entity)
    investments = Investment.where(investee_entity_id: entity.id,
                                   investment_instrument: %w[Equity Preferred Options])
                            .joins(:investor).includes(:investor)
    diluted = investments.group_by { |i| i.investor.investor_name }
                         .map { |k, v| [k, v.inject(0) { |sum, e| sum + e.percentage_holding }] }

    pie_chart_with_options diluted
  end

  def investment_undiluted(entity)
    investments = Investment.where(investee_entity_id: entity.id,
                                   investment_instrument: %w[Equity Preferred Options])
                            .joins(:investor).includes(:investor)

    undiluted = investments.group_by { |i| i.investor.investor_name }
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + e.diluted_percentage }] }

    pie_chart_with_options undiluted
  end

  def investment_by_intrument(entity)
    investments = Investment.where(investee_entity_id: entity.id)
                            .group_by(&:investment_instrument)
                            .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_cents / 100) }] }
                            .sort_by { |_k, v| v }.reverse

    column_chart investments, library: {
      plotOptions: { column: {
        dataLabels: {
          enabled: true,
          format: "{point.y:,.2f}"
        }
      } }
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
                   } }
                 }, decimal: ",", prefix: "#{entity.currency}:"
  end

  def investment_by_investor(entity)
    # We cant use the DB, as values are encrypted
    column_chart Investment.where(investee_entity_id: entity.id)
                           .joins(:investor).includes(:investor).group_by { |i| i.investor.investor_name }
                           .map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_cents / 100) }] }
                           .sort_by { |_k, v| v }.reverse,
                 library: {
                   plotOptions: { column: {
                     dataLabels: {
                       enabled: true,
                       format: "{point.y:,.2f}"
                     }
                   } }
                 }, decimal: ",", prefix: "#{entity.currency}:"
  end

  def count_by_investor(entity)
    pie_chart Investor.where(investee_entity_id: entity.id)
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
                }
              },
              donut: true
  end

  def notes_by_month(entity)
    notes = Note.where(entity_id: entity.id)
                .group('MONTH(created_at)')
    group_by_month = notes.count.sort.to_h.transform_keys { |k| I18n.t('date.month_names')[k] }
    column_chart group_by_month
  end

  def investor_interaction(entity)
    investors = Investor.where("investee_entity_id =? and last_interaction_date > ?", entity.id, Time.zone.today - 6.months)
                        .group('MONTH(last_interaction_date)')
    group_by_month = investors.count.sort.to_h.transform_keys { |k| I18n.t('date.month_names')[k] }
    column_chart group_by_month
  end
end
