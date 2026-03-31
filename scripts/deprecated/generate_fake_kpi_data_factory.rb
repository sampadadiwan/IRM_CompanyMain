require 'factory_bot_rails'

Chewy.strategy(:atomic) do
  entity_id = 157
  user = User.find_by(entity_id: entity_id) || User.first
  
  puts "Using entity_id: #{entity_id}"
  puts "Using user_id: #{user&.id}"

  # Portfolio Company Names
  portco_names = ["Apex Tech v2", "CloudSphere v2", "BioPulse v2"]

  portco_names.each do |name|
    puts "Creating data for #{name} using FactoryBot..."
    
    # 1. Create Portfolio Entity
    portco_email = "contact@#{name.downcase.gsub(' ', '')}.com"
    portco_entity = Entity.find_or_create_by!(name: "#{name} Entity") do |e|
      e.entity_type = "Portfolio Company"
      e.primary_email = portco_email
      # Add other fields that factory would have added
      e.enable_kpis = true
      e.currency = "USD"
    end

    # 2. Create Investor record (The "Portfolio Company" within the main entity)
    portco = Investor.find_or_create_by!(
      investor_name: name,
      entity_id: entity_id
    ) do |i|
      i.investor_entity_id = portco_entity.id
      i.category = "Portfolio Company"
      i.sector = ["SaaS", "HealthTech", "Logistics"].sample
      i.primary_email = portco_email
      i.tag_list = "Portfolio"
    end

    # 3. Create InvestorKpiMappings
    mappings = {}
    [
      { name: "MRR", category: "Operational Metrics" },
      { name: "EBITDA", category: "Income Statement" },
      { name: "Cash Burn", category: "Cashflow Statement" }
    ].each do |m|
      mappings[m[:name]] = InvestorKpiMapping.find_or_create_by!(
        entity_id: entity_id,
        investor_id: portco.id,
        standard_kpi_name: m[:name]
      ) do |ikm|
        ikm.reported_kpi_name = m[:name]
        ikm.category = m[:category]
      end
    end

    # 4. Create Investments
    # We use Investment.create! or FactoryBot.create(:investment)
    # The factory for :investment in test/factories.rb uses entity.investors.portfolio_companies.sample
    # so we might need to be careful with its internal logic.
    # Let's override to ensure it matches our needs.
    
    FactoryBot.create(:investment,
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      funding_round: "Seed",
      investment_type: "Equity",
      category: "Other",
      amount_cents: 50000000,
      currency: "USD",
      investment_date: 1.year.ago
    )

    FactoryBot.create(:investment,
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      funding_round: "Series A",
      investment_type: "Equity",
      category: "Other",
      amount_cents: 200000000,
      currency: "USD",
      investment_date: 6.months.ago
    )

    # 4. Create KPI Reports and KPIs
    (0..3).each do |i|
      as_of = (Date.today.beginning_of_quarter - (i * 3).months).end_of_quarter
      
      report = FactoryBot.create(:kpi_report,
        portfolio_company_id: portco.id,
        entity_id: entity_id,
        as_of: as_of,
        period: "Quarter",
        user_id: user&.id,
        tag_list: "Actual",
        analysis: "FactoryBot generated performance analysis for #{name} as of #{as_of}.",
        autofill_completed: true
      )

      # Create KPIs
      [
        { name: "MRR", base: 150000, var: 30000 },
        { name: "EBITDA", base: -10000, var: 5000 },
        { name: "Cash Burn", base: 25000, var: 8000 }
      ].each do |kpi_data|
        val = kpi_data[:base] + rand(kpi_data[:var])
        
        FactoryBot.create(:kpi,
          kpi_report_id: report.id,
          portfolio_company_id: portco.id,
          entity_id: entity_id,
          investor_kpi_mapping_id: mappings[kpi_data[:name]].id,
          name: kpi_data[:name],
          value: val,
          display_value: "$#{val}",
          status: "approved",
          rag_status: (kpi_data[:name] == "Cash Burn" ? { status: (val > 30000 ? "Red" : "Green") } : nil)
        )
      end
    end
  end
end

puts "Done creating fake data with FactoryBot!"
