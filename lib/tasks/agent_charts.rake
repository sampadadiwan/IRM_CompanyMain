namespace :agent_charts do
  # Chart definitions to seed. Each entry maps directly to AgentChart columns.
  # kpi_names must match the standard_kpi_name values in InvestorKpiMapping for the entity.
  # tag_list must match portfolio company tag_list values so AgentChartJob can resolve them.
  CHART_DEFINITIONS = [
    {
      title:             "Revenue & EBITDA Trend",
      prompt:            "Line chart showing Revenue and EBITDA over time. " \
                         "Use months as labels on the X axis, values in INR Cr on the Y axis. " \
                         "Include two datasets: one for Revenue and one for EBITDA.",
      kpi_names:         %w[Revenue EBITDA],
      kpi_before:        12,
      kpi_before_period: "Month",
      tag_list:          "Ecommerce",
    },
    {
      title:             "Gross Profit vs COGS Breakdown",
      prompt:            "Stacked bar chart comparing Revenue, COGS, and Gross Profit per period. " \
                         "Labels are quarters. Show three datasets side by side so the fund manager " \
                         "can see margin compression or expansion at a glance.",
      kpi_names:         ["Revenue", "COGS", "GROSS PROFIT"],
      kpi_before:        8,
      kpi_before_period: "Quarter",
      tag_list:          "D2C",
    },
    {
      title:             "Contribution Margin Analysis",
      prompt:            "Bar chart with two datasets: Revenue and Contribution. " \
                         "Overlay a line for Contribution Margin % if possible, otherwise show it " \
                         "as a third bar dataset. Use quarters as labels.",
      kpi_names:         ["Revenue", "Contribution", "Contribution Margin"],
      kpi_before:        8,
      kpi_before_period: "Quarter",
      tag_list:          nil,  # no tag — applies to all portfolio companies
    },
    {
      title:             "Annual Revenue Growth",
      prompt:            "Bar chart showing Net Sales for each financial year. " \
                         "Sort labels chronologically (oldest to newest). Add a label on each bar " \
                         "showing the year-on-year growth percentage if data allows.",
      kpi_names:         ["Net Sales", "Revenue"],
      kpi_before:        5,
      kpi_before_period: "Annual",
      tag_list:          "Ecommerce",
    },
    {
      title:             "Skincare & Beauty KPI Dashboard",
      prompt:            "Multi-dataset bar chart comparing Revenue, EBITDA, and Contribution for " \
                         "the last 6 months for D2C beauty/skincare portfolio companies. " \
                         "Use months as X axis labels.",
      kpi_names:         %w[Revenue EBITDA Contribution],
      kpi_before:        6,
      kpi_before_period: "Month",
      tag_list:          "beauty,skincare",
    },
  ].freeze

  desc <<~DESC
    Seed standard agent chart definitions for a given entity.

    Usage:
      rake agent_charts:seed ENTITY_ID=157

    The task is idempotent — it skips any chart whose title already exists for
    the entity, so it is safe to run multiple times.
  DESC
  task seed: :environment do
    entity_id = ENV.fetch("ENTITY_ID") do
      abort "ERROR: ENTITY_ID is required. Usage: rake agent_charts:seed ENTITY_ID=<id>"
    end.to_i

    entity = Entity.find_by(id: entity_id)
    abort "ERROR: Entity #{entity_id} not found." unless entity

    puts "Seeding agent charts for entity #{entity_id} (#{entity.name})…"
    puts

    created = 0
    skipped = 0

    CHART_DEFINITIONS.each do |defn|
      existing = AgentChart.find_by(entity: entity, title: defn[:title])

      if existing
        puts "  SKIP  #{defn[:title]} (already exists as ##{existing.id})"
        skipped += 1
        next
      end

      chart = AgentChart.create!(
        entity:            entity,
        title:             defn[:title],
        prompt:            defn[:prompt],
        kpi_names:         defn[:kpi_names],
        kpi_before:        defn[:kpi_before],
        kpi_before_period: defn[:kpi_before_period],
        tag_list:          defn[:tag_list],
        status:            "draft",
      )

      tag_display = defn[:tag_list].presence || "(all companies)"
      puts "  CREATE ##{chart.id}  #{chart.title}  [#{tag_display}]"
      created += 1
    end

    puts
    puts "Done — #{created} created, #{skipped} skipped."
  end
end
