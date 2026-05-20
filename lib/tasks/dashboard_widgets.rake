namespace :irm do
  namespace :dashboard_widgets do
    desc "Configure default LP Landing Page widgets for an entity. Usage: rake irm:dashboard_widgets:setup_lp[157]"
    task :setup_lp, [:entity_id] => :environment do |_t, args|
      entity_id = args[:entity_id].to_i
      raise "entity_id required" if entity_id.zero?

      entity = Entity.find(entity_id)
      puts "Configuring LP Landing Page widgets for: #{entity.name} (id: #{entity_id})"

      # Default widget configs for LP Landing Page — position-ordered
      defaults = [
        { widget_name: "Funds",                path: "entities/widgets/lp_funds",                size: "XL",     tags: "Funds",                metadata: nil },
        { widget_name: "LP Menus",             path: "entities/widgets/lp_menus",                size: "XL",     tags: "Quick Links",          metadata: "{card_type: 'card2'}" },
        { widget_name: "LP Header",            path: "entities/widgets/lp_header",               size: "XL",     tags: "Notice",               metadata: "{title: 'Welcome', content: 'Welcome to your investor dashboard.', style: 'info', show_date: false}" },
        { widget_name: "LP Metric Cards",      path: "entities/widgets/lp_metric_cards",         size: "XL",     tags: "Key Metrics",          metadata: "{metrics: 'Committed,Called,Distributed', per_row: 4}" },
        { widget_name: "LP Action Items",      path: "entities/widgets/lp_action_items",         size: "Medium", tags: "Action Items",         metadata: "{show_calls: true, show_kyc: true, show_approvals: true, max_items: 10}" },
        { widget_name: "LP Latest Documents",  path: "entities/widgets/lp_latest_documents",     size: "Medium", tags: "Documents",            metadata: "{per_page: 5, show_library_link: true}" },
        { widget_name: "LP Performance Chart", path: "entities/widgets/lp_performance_chart",    size: "Large",  tags: "Performance Overview", metadata: "{series: 'Called,Distributed', cumulative: true, chart_type: 'area', months: 36, aggregate_by: 'quarter'}" },
        { widget_name: "LP Ratios Chart",      path: "entities/widgets/lp_ratios_chart",         size: "Medium", tags: "Return Multiples",     metadata: "{ratio_names: ['TVPI','DPI','MOIC'], for_fund: true, title: 'Return Multiples', timeseries: true, months: 24, list: false, chart: true}" },
        { widget_name: "LP Ratios Chart",      path: "entities/widgets/lp_ratios_chart",         size: "Medium", tags: "IRR",                  metadata: "{ratio_names: ['XIRR'], for_fund: true, title: 'IRR', timeseries: true, months: 24, list: false, chart: true}" },
        { widget_name: "Investment Opportunities", path: "entities/widgets/lp_investment_opportunities", size: "XL", tags: "Opportunities",  metadata: nil },
      ]

      created = 0
      skipped = 0

      defaults.each_with_index do |cfg, idx|
        position = idx + 1
        # Skip if an identical widget_name+tags combo already exists
        existing = DashboardWidget.find_by(
          dashboard_name: DashboardWidget::LP_LANDING_PAGE,
          entity_id:      entity_id,
          widget_name:    cfg[:widget_name],
          tags:           cfg[:tags]
        )

        if existing
          puts "  SKIP  pos=#{position} #{cfg[:widget_name]} (#{cfg[:tags]}) — already exists (id: #{existing.id})"
          skipped += 1
          next
        end

        w = DashboardWidget.create!(
          dashboard_name: DashboardWidget::LP_LANDING_PAGE,
          entity_id:      entity_id,
          widget_name:    cfg[:widget_name],
          size:           cfg[:size],
          tags:           cfg[:tags],
          position:       position,
          metadata:       cfg[:metadata],
          enabled:        true
        )
        puts "  CREATE pos=#{w.position} #{w.widget_name} (#{w.tags}) — id: #{w.id}"
        created += 1
      end

      puts "\nDone — created: #{created}, skipped: #{skipped}"
    end

    desc "Configure default FM Landing Page widgets for an entity. Usage: rake irm:dashboard_widgets:setup_fm[157]"
    task :setup_fm, [:entity_id] => :environment do |_t, args|
      entity_id = args[:entity_id].to_i
      raise "entity_id required" if entity_id.zero?

      entity = Entity.find(entity_id)
      puts "Configuring FM Landing Page widgets for: #{entity.name} (id: #{entity_id})"

      defaults = [
        { widget_name: "FM Menus",                path: "entities/widgets/fm_menus",                size: "XL",     tags: "Quick Links",       metadata: "{card_type: 'card2'}" },
        { widget_name: "FM Stats",                path: "entities/widgets/fm_stats",                size: "XL",     tags: "Fund Stats",        metadata: nil },
        { widget_name: "Funds",                   path: "entities/widgets/funds",                   size: "XL",     tags: "Funds",             metadata: nil },
        { widget_name: "Investment Opportunities", path: "entities/widgets/investment_opportunities", size: "XL",   tags: "Opportunities",     metadata: nil },
      ]

      created = 0
      skipped = 0

      defaults.each_with_index do |cfg, idx|
        position = idx + 1
        existing = DashboardWidget.find_by(
          dashboard_name: DashboardWidget::FM_LANDING_PAGE,
          entity_id:      entity_id,
          widget_name:    cfg[:widget_name],
          tags:           cfg[:tags]
        )

        if existing
          puts "  SKIP  pos=#{position} #{cfg[:widget_name]} — already exists (id: #{existing.id})"
          skipped += 1
          next
        end

        w = DashboardWidget.create!(
          dashboard_name: DashboardWidget::FM_LANDING_PAGE,
          entity_id:      entity_id,
          widget_name:    cfg[:widget_name],
          size:           cfg[:size],
          tags:           cfg[:tags],
          position:       position,
          metadata:       cfg[:metadata],
          enabled:        true
        )
        puts "  CREATE pos=#{w.position} #{w.widget_name} (#{w.tags}) — id: #{w.id}"
        created += 1
      end

      puts "\nDone — created: #{created}, skipped: #{skipped}"
    end

    desc "Configure both LP and FM Landing Page widgets for an entity. Usage: rake irm:dashboard_widgets:setup_all[157]"
    task :setup_all, [:entity_id] => :environment do |_t, args|
      Rake::Task["irm:dashboard_widgets:setup_lp"].invoke(args[:entity_id])
      Rake::Task["irm:dashboard_widgets:setup_fm"].invoke(args[:entity_id])
    end
  end
end
