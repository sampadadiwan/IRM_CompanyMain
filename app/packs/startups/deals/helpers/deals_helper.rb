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

  def deal_investors_added_by_month(deal)
    data = deal.deal_investors
               .where.not(created_at: nil)
               .order(:created_at)
               .pluck(:created_at)
               .group_by { |t| t.strftime("%b %Y") }
               .transform_values(&:count)

    bar_chart data, id: "chart-investors-by-month", library: {
      xAxis: { type: 'datetime', labels: { format: '{value:%b %Y}' } },
      yAxis: { title: { text: 'Investors Added' }, allowDecimals: false },
      **chart_theme_color
    }
  end

  def deal_investors_status(deal)
    deal_investors = deal.deal_investors.joins(:investor).group(:status).count

    pie_chart deal_investors, donut: true, id: "chart-deal-status", library: {
      plotOptions: {
        pie: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>:<br>{point.percentage:.1f}% <br>Count: {point.y}'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_activities_completion(deal)
    deal_activities = deal.deal_activities.unscoped.joins(:deal_investor)
                          .merge(DealInvestor.not_declined).group(:status).count

    pie_chart deal_activities, donut: true, id: "chart-deal-activities", library: {
      plotOptions: {
        pie: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>:<br>{point.percentage:.1f}% <br>Count: {point.y}'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_conversion_funnel(deal)
    # Define the stages of the funnel
    stages = ['Active','New', 'Interested', 'In Progress', 'Committed', 'Complete']
    counts = deal.deal_investors.group(:status).count


    # Map the counts to the stages, ensuring all stages are represented
    data = stages.map { |stage| [stage, counts[stage] || 0] }

    # We use a column chart with horizontal orientation or specialized funnel options if available
    bar_chart data, id: "chart-deal-funnel", library: {
      plotOptions: {
        series: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>: {point.y}'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_commitment_velocity(deal)
    investors = deal.deal_investors.where(status: %w[Active Committed Complete]).order(:created_at)

    # Group by date and calculate running total
    cumulative_amount = 0
    data = investors.group_by { |i| i.created_at.to_date }.map do |date, group|
      cumulative_amount += group.sum(&:total_amount).to_f
      [date, cumulative_amount]
    end

    area_chart data, id: "chart-deal-velocity", prefix: deal.currency, library: {
      xAxis: { type: 'datetime', labels: { format: '{value:%b %d}' } },
      **chart_theme_color
    }
  end

  def deal_weighted_pipeline(deal)
    probabilities = {
      'New' => 0.05,
      'Interested' => 0.25,
      'In Progress' => 0.50,
      'Committed' => 1.0,
      'Complete' => 1.0
    }

    counts = deal.deal_investors.group(:status).sum(:total_amount_cents)
    weighted_total = counts.sum { |status, cents| (cents / 100.0) * (probabilities[status] || 0) }

    data = [
      ["Target", deal.amount.to_f],
      ["Weighted Pipeline", weighted_total]
    ]

    column_chart data, id: "chart-deal-weighted", prefix: deal.currency, library: {
      **chart_theme_color
    }
  end

  def deal_activity_efficiency(deal)
    # Average days to complete each activity template
    # Since we don't have "completed_at" easily on DealActivity, we'll use updated_at if status is Complete
    activities = deal.deal_activities.unscoped.where(status: 'Complete').joins(:deal_investor).merge(DealInvestor.not_declined)

    # Group by title and average (updated_at - created_at)
    # This is a proxy for how long it took to complete
    diff_sql = if Rails.env.test?
                 "julianday(deal_activities.updated_at) - julianday(deal_activities.created_at)"
               else
                 "DATEDIFF(deal_activities.updated_at, deal_activities.created_at)"
               end
    data = activities.group(:title).average(diff_sql)
    data = data.map { |title, avg| [title, avg.to_f.round(1)] }.sort_by { |_, avg| -avg }

    bar_chart data, id: "chart-deal-efficiency", xtitle: "Avg Days to Complete", library: {
      **chart_theme_color
    }
  end

  def deal_investor_concentration(deal)
    data = deal.deal_investors.not_declined.group(:source).sum(:total_amount_cents)
    data = data.map { |source, cents| [source.presence || "Unknown", cents / 100.0] }

    pie_chart data, donut: true, id: "chart-deal-source", library: {
      plotOptions: {
        pie: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>: {point.percentage:.1f}%'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_investor_concentration_by_tier(deal)
    data = deal.deal_investors.not_declined.group(:tier).sum(:total_amount_cents)
    data = data.map { |tier, cents| [tier.presence || "Unknown", cents / 100.0] }

    pie_chart data, donut: true, id: "chart-deal-tier", library: {
      plotOptions: {
        pie: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>: {point.percentage:.1f}%'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_investor_concentration_by_lead(deal)
    data = deal.deal_investors.not_declined.group(:deal_lead).sum(:total_amount_cents)
    data = data.map { |lead, cents| [lead.presence || "Unknown", cents / 100.0] }

    pie_chart data, donut: true, id: "chart-deal-lead", library: {
      plotOptions: {
        pie: {
          cursor: 'pointer',
          dataLabels: {
            enabled: true,
            format: '<b>{point.name}</b>: {point.percentage:.1f}%'
          }
        }
      },
      **chart_theme_color
    }
  end

  def deal_days_in_stage(deal)
    # Distribution of days since last status update
    investors = deal.deal_investors.not_declined.where.not(status: %w[Complete Declined])

    # Categorize into bins
    bins = { '0-7 days' => 0, '8-14 days' => 0, '15-30 days' => 0, '30+ days' => 0 }
    investors.each do |i|
      days = (Time.current - i.updated_at).to_i / 1.day
      if days <= 7
        bins['0-7 days'] += 1
      elsif days <= 14
        bins['8-14 days'] += 1
      elsif days <= 30
        bins['15-30 days'] += 1
      else
        bins['30+ days'] += 1
      end
    end

    column_chart bins, id: "chart-deal-days", library: {
      plotOptions: {
        series: {
          cursor: 'pointer'
        }
      },
      **chart_theme_color
    }
  end

  # Aggregate Analytics for Deals Index

  def deals_status_chart(deals)
    data = deals.group(:status).count
    pie_chart data, donut: true, id: "deals-status-chart", library: {
      title: { text: "Deal Status" },
      **chart_theme_color
    }
  end

  def deals_by_currency_chart(deals)
    data = deals.group(:currency).sum(:amount_cents)
    data = data.map { |curr, cents| [curr, cents / 100.0] }
    column_chart data, id: "deals-currency-chart", library: {
      title: { text: "Total Amount by Currency" },
      plotOptions: {
        column: { colorByPoint: true }
      },
      **chart_theme_color
    }
  end

  def deals_by_tag_chart(deals)
    tags = deals.pluck(:tags).compact.flat_map { |t| t.split(",").map(&:strip) }
    data = tags.tally.sort_by { |_tag, count| -count }.first(10)
    bar_chart data, id: "deals-tag-chart", library: {
      title: { text: "Top 10 Tags" },
      plotOptions: {
        bar: { colorByPoint: true }
      },
      **chart_theme_color
    }
  end

  def global_investor_pipeline_chart(deals)
    data = DealInvestor.where(deal_id: deals.pluck(:id)).group(:status).count
    stages = ['New', 'Interested', 'In Progress', 'Committed', 'Complete']
    sorted_data = stages.map { |stage| [stage, data[stage] || 0] }

    bar_chart sorted_data, id: "global-pipeline-chart", library: {
      title: { text: "Global Investor Pipeline" },
      plotOptions: {
        bar: { colorByPoint: true }
      },
      **chart_theme_color
    }
  end

  def deals_volume_trend_chart(deals)
    # Group by month using SQL to avoid Groupdate timezone restriction
    # Using COALESCE to fallback to created_at if start_date is null
    group_sql = if Rails.env.test?
                  "strftime('%Y-%m-01', COALESCE(start_date, created_at))"
                else
                  "DATE_FORMAT(COALESCE(start_date, created_at), '%Y-%m-01')"
                end
    data = deals.group(group_sql).count
    # Convert keys to Date objects for better display in Chartkick
    data = data.transform_keys { |k| Date.parse(k) }

    area_chart data, id: "deals-volume-chart", library: {
      title: { text: "Deal Volume Trend" },
      **chart_theme_color
    }
  end

  def top_deals_chart(deals)
    data = deals.order(amount_cents: :desc).limit(5).map { |d| [d.name, d.amount.to_f] }
    bar_chart data, id: "top-deals-chart", library: {
      title: { text: "Top 5 Deals by Amount" },
      plotOptions: {
        bar: { colorByPoint: true }
      },
      **chart_theme_color
    }
  end

  def aggregate_investor_sources_chart(deals)
    data = DealInvestor.where(deal_id: deals.pluck(:id)).group(:source).count
    data = data.transform_keys { |k| k.presence || "Unknown" }
    pie_chart data, donut: true, id: "aggregate-sources-chart", library: {
      title: { text: "Investor Sources" },
      **chart_theme_color
    }
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
