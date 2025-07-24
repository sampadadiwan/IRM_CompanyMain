module DealsHelper
  def deals_pie(deals)
    deals = deals.group_by(&:name).map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.amount_cents / 100) }] }

    column_chart deals, library: {
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

  def deal_investors_money(deal)
    deal_investors = deal.deal_investors.not_declined.joins(:investor).group_by { |d| d.investor.investor_name }
    pre_money = deal_investors.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.pre_money_valuation_cents / 100) }] }
    primary = deal_investors.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.primary_amount_cents / 100) }] }
    secondary = deal_investors.map { |k, v| [k, v.inject(0) { |sum, e| sum + (e.secondary_investment_cents / 100) }] }

    data = [
      { name: "Pre Money", data: pre_money },
      { name: "Primary", data: primary },
      { name: "Secondary", data: secondary }
    ]

    column_chart data, prefix: deal.currency, library: {
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

  def deal_investors_status(deal)
    deal_investors = deal.deal_investors.joins(:investor).group(:status).count

    pie_chart deal_investors, library: { plotOptions: { pie: {
      dataLabels: {
        enabled: true,
        format: '<b>{point.name}</b>:<br>{point.percentage:.1f}% <br>Count: {point.y}'
      }
    } },
                                         **chart_theme_color }
  end

  def deal_activities_completion(deal)
    deal_activities = deal.deal_activities.unscoped.joins(:deal_investor)
                          .merge(DealInvestor.not_declined).group(:completed).count

    deal_activities = deal_activities.map { |k, v| k ? ["Completed", v] : ["Incomplete", v] }

    pie_chart deal_activities, library: { plotOptions: { pie: {
      dataLabels: {
        enabled: true,
        format: '<b>{point.name}</b>:<br>{point.percentage:.1f}% <br>Count: {point.y}'
      }
    } },
                                          **chart_theme_color }
  end

  def kanban_funnel_data(deal)
    deal.kanban_board.kanban_columns.map do |column|
      [column.name, column.kanban_cards.count]
    end
  end

  def get_grouped_access_rights(access_rights)
    access_rights.includes(:granted_by).group_by do |ar|
      if ar.access_to_investor_id.present?
        [:access_to_investor_id, ar.access_to_investor_id]
      elsif ar.access_to_category.present?
        [:access_to_category, ar.access_to_category]
      else
        [:user_id, ar.user_id]
      end
    end
  end

  def filter_by_owner(grouped_access_rights, access)
    case access
    when "both"
      grouped_access_rights = grouped_access_rights.select do |_, access_rights|
        access_rights.many?
      end
    when "deal"
      grouped_access_rights = grouped_access_rights.select do |_, access_rights|
        access_rights.any? { |ar| ar.owner_type == "Deal" }
      end
    when "folder"
      grouped_access_rights = grouped_access_rights.select do |_, access_rights|
        access_rights.any? { |ar| ar.owner_type == "Folder" }
      end
    end
    grouped_access_rights
  end
end
