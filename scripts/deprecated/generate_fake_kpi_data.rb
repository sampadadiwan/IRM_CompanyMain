Chewy.strategy(:atomic) do
  entity_id = 157
  user = User.find_by(entity_id: entity_id) || User.first
  user_id = user&.id

  puts "Using entity_id: #{entity_id}"
  puts "Using user_id: #{user_id}"

  # Portfolio Company Names
  portco_names = ["Acme Corp", "TechNova", "BioGen"]

  portco_names.each do |name|
    puts "Creating data for #{name}..."
    
    # Create a new entity for the portfolio company to act as its own "investor_entity"
    # This is often how portcos are set up in IRM to allow them to log in.
    portco_email = "contact@#{name.downcase.gsub(' ', '')}.com"
    portco_entity = Entity.find_or_create_by!(name: "#{name} Entity") do |e|
      e.entity_type = "Portfolio Company"
      e.primary_email = portco_email
    end
    
    # Create Investor (as Portfolio Company)
    portco = Investor.find_or_create_by!(
      investor_name: name,
      entity_id: entity_id
    ) do |i|
      i.investor_entity_id = portco_entity.id
      i.category = "Portfolio Company"
      i.sector = ["SaaS", "FinTech", "HealthTech"].sample
      i.primary_email = portco_email
      i.tag_list = "Portfolio"
    end

    # Create some Investments
    [
      { type: "Equity", category: "Other", round: "Seed", amount: 50000000, date: 1.year.ago },
      { type: "Equity", category: "Other", round: "Series A", amount: 200000000, date: 6.months.ago }
    ].each do |inv_data|
      Investment.find_or_create_by!(
        portfolio_company_id: portco.id,
        entity_id: entity_id,
        funding_round: inv_data[:round]
      ) do |inv|
        inv.category = inv_data[:category]
        inv.investment_type = inv_data[:type]
        inv.amount_cents = inv_data[:amount]
        inv.currency = "USD"
        inv.investment_date = inv_data[:date]
        inv.quantity = 1000
        inv.price_cents = inv_data[:amount] / 1000
      end
    end

    # Create KPI Reports for the last 4 quarters
    (0..3).each do |i|
      as_of = (Date.today.beginning_of_quarter - (i * 3).months).end_of_quarter
      report = KpiReport.find_or_create_by!(
        portfolio_company_id: portco.id,
        entity_id: entity_id,
        as_of: as_of,
        period: "Quarter"
      ) do |r|
        r.user_id = user_id
        r.tag_list = "Actual"
        r.analysis = "Performance for #{as_of.strftime('%B %Y')} was strong."
        r.autofill_completed = true
      end

      # Create KPIs for each report
      kpis_to_create = [
        { name: "MRR", base: 100000, var: 50000 },
        { name: "EBITDA", base: -20000, var: 10000 },
        { name: "Cash Burn", base: 30000, var: 5000 }
      ]

      kpis_to_create.each do |kpi_data|
        val = kpi_data[:base] + rand(kpi_data[:var])
        
        Kpi.find_or_create_by!(
          kpi_report_id: report.id,
          portfolio_company_id: portco.id,
          entity_id: entity_id,
          name: kpi_data[:name]
        ) do |k|
          k.value = val
          k.display_value = "$#{val}"
          k.status = "approved"
          if kpi_data[:name] == "Cash Burn"
            k.rag_status = { status: (val > 33000 ? "Red" : "Green") }
          end
        end
      end
    end
  end
end

puts "Done!"
