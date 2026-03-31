require 'factory_bot_rails'

# Unified Script to generate data for KPI Data Models and AI Queries
# Based on docs/ai_instructions/kpi_data_models.md

Chewy.strategy(:atomic) do
  entity_id = 157
  user = User.find_by(entity_id: entity_id) || User.first
  user_id = user&.id

  puts "Using entity_id: #{entity_id}"
  puts "Using user_id: #{user_id}"

  # 1. Setup Main Fund
  fund = Fund.find_or_create_by!(entity_id: entity_id, name: "IRM Catalyst Fund I") do |f|
    f.currency = "USD"
    f.category = "VC"
  end

  # 2. Portfolio Companies to generate
  portcos_config = [
    { name: "Acme Corp", sector: "SaaS", status: "Active" },
    { name: "TechNova", sector: "FinTech", status: "Active" },
    { name: "BioGen", sector: "HealthTech", status: "Active" },
    { name: "EcoFlow", sector: "CleanTech", status: "Active" },
    { name: "CyberShield", sector: "Cybersecurity", status: "Active" }
  ]

  portcos_config.each do |config|
    name = config[:name]
    puts "Generating data for #{name}..."

    # Create Portfolio Entity (multi-tenant scope for the portco itself)
    portco_email = "finance@#{name.downcase.gsub(' ', '')}.com"
    portco_entity = Entity.find_or_create_by!(name: "#{name} Entity") do |e|
      e.entity_type = "Portfolio Company"
      e.primary_email = portco_email
      e.enable_kpis = true
      e.currency = "USD"
    end

    # Create Investor record (The "Portfolio Company" within the main entity)
    portco = Investor.find_or_create_by!(
      investor_name: name,
      entity_id: entity_id
    ) do |i|
      i.investor_entity_id = portco_entity.id
      i.category = "Portfolio Company"
      i.sector = config[:sector]
      i.primary_email = portco_email
      i.tag_list = "Portfolio"
    end

    # Create another holding entity for Query 10
    if name == "TechNova"
      Investor.find_or_create_by!(
        investor_name: "TechNova Holdings SPV",
        entity_id: entity_id
      ) do |i|
        i.primary_email = "holdings@technova.com"
        i.category = "Holding Company"
        i.is_holdings_entity = true
        i.tag_list = "SPV"
      end

      # Add an investment for this SPV
      Investment.find_or_create_by!(
        portfolio_company_id: portco.id,
        entity_id: entity_id,
        funding_round: "Series A",
        investor_name: "TechNova Holdings SPV"
      ) do |inv|
        inv.category = "Other"
        inv.investment_date = 1.year.ago
        inv.investment_type = "Equity"
        inv.amount_cents = 200_000_000 # $2M
        inv.currency = "USD"
        inv.quantity = 100_000
        inv.price_cents = 2000
        inv.instrument_name = "Preferred Stock"
      end
    end

    # 3. Create InvestorKpiMappings (Templates for KPIs)
    mappings = {}
    [
      { name: "MRR", category: "Operational Metrics" },
      { name: "EBITDA", category: "Income Statement" },
      { name: "Cash Burn", category: "Cashflow Statement" },
      { name: "Revenue", category: "Income Statement" },
      { name: "Marketing Spend", category: "Operational Metrics" }
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

    # 4. Create Investments (Transactions)
    # Seed Round
    Investment.find_or_create_by!(
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      funding_round: "Seed",
      investor_name: "IRM Catalyst Fund I"
    ) do |inv|
      inv.investment_date = 2.years.ago
      inv.investment_type = "Equity"
      inv.category = "Other"
      inv.amount_cents = 100_000_000 # $1M
      inv.currency = "USD"
      inv.quantity = 100_000
      inv.price_cents = 1000 # $10.00
      inv.instrument_name = "Common Stock"
    end

    # Also add other investors to Seed round (Query 19)
    if name == "Acme Corp"
      ["Global Ventures", "Angel Syndicate"].each do |other_investor|
        Investment.find_or_create_by!(
          portfolio_company_id: portco.id,
          entity_id: entity_id,
          funding_round: "Seed",
          investor_name: other_investor
        ) do |inv|
          inv.category = "Other"
          inv.investment_date = 2.years.ago
          inv.investment_type = "Equity"
          inv.amount_cents = 50_000_000
          inv.currency = "USD"
          inv.quantity = 50_000
          inv.price_cents = 1000
          inv.instrument_name = "Common Stock"
        end
      end
    end

    # Series A (Primary)
    Investment.find_or_create_by!(
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      funding_round: "Series A"
    ) do |inv|
      inv.investment_date = 1.year.ago
      inv.investment_type = "Equity"
      inv.category = "Other"
      inv.amount_cents = 500_000_000 # $5M
      inv.currency = (name == "EcoFlow" ? "INR" : "USD") # Query 13
      inv.quantity = 250_000
      inv.price_cents = 2000 # $20.00
      inv.instrument_name = "Preferred Stock"
      inv.investor_name = "IRM Catalyst Fund I"
    end

    # Secondary transaction for Acme Corp specifically (to answer Query 29)
    if name == "Acme Corp"
      Investment.find_or_create_by!(
        portfolio_company_id: portco.id,
        entity_id: entity_id,
        funding_round: "Series A",
        investment_date: 6.months.ago,
        investment_type: "Equity"
      ) do |inv|
        inv.category = "Other"
        inv.amount_cents = 50_000_000 # $500k
        inv.currency = "USD"
        inv.quantity = 25_000
        inv.price_cents = 2000
        inv.instrument_name = "Common Stock"
        inv.investor_name = "IRM Catalyst Fund I"
        inv.notes = "Secondary purchase" # To answer Query 9/29
      end
    end

    # 5. Setup Portfolio Investment Tracking (Core Infrastructure)
    common_instrument = InvestmentInstrument.find_or_create_by!(
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      name: "Common Equity - #{name}"
    ) do |ii|
      ii.category = "Unlisted"
      ii.sub_category = "Equity"
      ii.sector = config[:sector]
      ii.currency = "USD"
    end

    preferred_instrument = InvestmentInstrument.find_or_create_by!(
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      name: "Preferred Stock - #{name}"
    ) do |ii|
      ii.category = "Unlisted"
      ii.sub_category = "Equity"
      ii.sector = config[:sector]
      ii.currency = "USD"
    end

    # Create valuations for both instruments (Query 40)
    (0..7).reverse_each do |i|
      val_date = (Date.today.beginning_of_quarter - (i * 3).months).end_of_quarter
      
      # Common: Gradually increasing valuation
      psv_common = 1000 + ((7-i) * 200) # Starts at 10.00, ends at 24.00
      
      Valuation.find_or_create_by!(
        entity_id: entity_id,
        owner: portco,
        investment_instrument_id: common_instrument.id,
        valuation_date: val_date
      ) do |v|
        v.per_share_value_cents = psv_common
      end

      # Preferred: Usually higher than common
      psv_preferred = 2000 + ((7-i) * 300) # Starts at 20.00, ends at 41.00
      
      Valuation.find_or_create_by!(
        entity_id: entity_id,
        owner: portco,
        investment_instrument_id: preferred_instrument.id,
        valuation_date: val_date
      ) do |v|
        v.per_share_value_cents = psv_preferred
      end
    end

    api_record = AggregatePortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      investment_instrument_id: common_instrument.id
    ) do |api|
      api.portfolio_company_name = name
      api.bought_amount_cents = 0
      api.sold_amount_cents = 0
      api.net_bought_amount_cents = 0
      api.fmv_cents = 0
      api.gain_cents = 0
    end

    # Link to PortfolioInvestment for detailed tracking
    PortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      investment_instrument_id: common_instrument.id,
      investment_date: 2.years.ago.to_date,
      aggregate_portfolio_investment_id: api_record.id
    ) do |pi|
      pi.base_amount_cents = 100_000_000
      pi.ex_expenses_base_amount_cents = 100_000_000
      pi.amount_cents = 100_000_000
      pi.net_bought_amount_cents = 100_000_000
      pi.net_amount_cents = 100_000_000
      pi.quantity = 100_000
      pi.category = "Unlisted"
      pi.sub_category = "Equity"
    end

    # Add Preferred stock PortfolioInvestment
    preferred_api_record = AggregatePortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      portfolio_company_id: portco.id,
      entity_id: entity_id,
      investment_instrument_id: preferred_instrument.id
    ) do |api|
      api.portfolio_company_name = name
      api.bought_amount_cents = 0
      api.sold_amount_cents = 0
      api.net_bought_amount_cents = 0
      api.fmv_cents = 0
      api.gain_cents = 0
    end

    PortfolioInvestment.find_or_create_by!(
      fund_id: fund.id,
      entity_id: entity_id,
      portfolio_company_id: portco.id,
      investment_instrument_id: preferred_instrument.id,
      investment_date: 1.year.ago.to_date,
      aggregate_portfolio_investment_id: preferred_api_record.id
    ) do |pi|
      pi.base_amount_cents = 500_000_000
      pi.ex_expenses_base_amount_cents = 500_000_000
      pi.amount_cents = 500_000_000
      pi.net_bought_amount_cents = 500_000_000
      pi.net_amount_cents = 500_000_000
      pi.quantity = 250_000
      pi.category = "Unlisted"
      pi.sub_category = "Equity"
    end

    # 6. Create KPI Reports and individual KPIs (Last 8 quarters)
    (0..7).reverse_each do |i|
      as_of = (Date.today.beginning_of_quarter - (i * 3).months).end_of_quarter

      # Create BOTH Actual and Budget for some quarters to allow variance analysis (Query 31)
      ["Actual", "Budget"].each do |type|
        report = KpiReport.find_or_create_by!(
          portfolio_company_id: portco.id,
          entity_id: entity_id,
          as_of: as_of,
          period: "Quarter",
          tag_list: type
        ) do |r|
          r.user_id = user_id
          r.analysis = "#{type} quarterly review for #{name}. Growth continues as expected in the #{config[:sector]} sector."
          r.autofill_completed = true
          r.enable_portco_upload = (rand > 0.5) # Query 15
        end

        # Add a Document to the report (Query 2)
        Document.find_or_create_by!(
          owner_type: "KpiReport",
          owner_id: report.id,
          entity_id: entity_id,
          name: "#{name}_#{as_of}_#{type}_Financials.pdf"
        ) do |doc|
          doc.user_id = user_id
          doc.tag_list = "Financial Statement"
          doc.file = File.open(Rails.root.join('public/sample_uploads/sample_kyc1.pdf'))
        end

        # KPIs for the report
        # Generate trending values
        mrr_base = 100_000 + ( (7-i) * 20_000 ) + rand(5000)
        # If budget, slightly different
        mrr_base *= 1.1 if type == "Budget"
        
        revenue_base = mrr_base * 1.2
        ebitda_base = -50_000 + ( (7-i) * 10_000 ) + rand(2000)
        burn_base = 40_000 - ( (7-i) * 2000 ) + rand(1000)
        marketing_base = revenue_base * 0.25

        kpis_data = [
          { name: "MRR", value: mrr_base },
          { name: "Revenue", value: revenue_base },
          { name: "EBITDA", value: ebitda_base },
          { name: "Cash Burn", value: burn_base },
          { name: "Marketing Spend", value: marketing_base }
        ]

        kpis_data.each do |kpi_item|
          val = kpi_item[:value]
          
          # Calculate simple QoQ percentage change for Query 26
          # (Very rough: random +/- 10%)
          pct_change = (rand * 20) - 10

          Kpi.find_or_create_by!(
            kpi_report_id: report.id,
            portfolio_company_id: portco.id,
            entity_id: entity_id,
            name: kpi_item[:name]
          ) do |k|
            k.investor_kpi_mapping_id = mappings[kpi_item[:name]]&.id
            k.value = val
            k.display_value = "$#{val.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse}"
            k.status = (rand > 0.1 ? "approved" : "unapproved") # Query 39
            k.source = "AI Extracted"
            k.approved_by_user_id = user_id if k.status == "approved" # Query 14
            k.percentage_change = pct_change
            k.notes = "Quarterly update for #{kpi_item[:name]} based on latest financials." # Query 32

            # Add RAG Status (Query 30, 32)
            if kpi_item[:name] == "EBITDA" && val < -45_000
              k.rag_status = { status: "Red", reason: "Burn higher than budget" }
            elsif kpi_item[:name] == "Cash Burn" && val > 35_000
              k.rag_status = { status: "Amber", reason: "Monitoring burn closely" }
            else
              k.rag_status = { status: "Green" }
            end

            # Common Size Value (Query 35, 50)
            if kpi_item[:name] == "Marketing Spend"
              k.common_size_value = (val / revenue_base) * 100
            end
          end
        end
      end

      # Monthly reports for the last 3 months to answer Query 36
      if i < 1
        [0, 1, 2].each do |m|
          month_as_of = (Date.today.beginning_of_month - m.months).end_of_month
          
          ["Actual", "Budget"].each do |type|
            KpiReport.find_or_create_by!(
              portfolio_company_id: portco.id,
              entity_id: entity_id,
              as_of: month_as_of,
              period: "Month",
              tag_list: type
            ) do |r|
              r.user_id = user_id
              r.analysis = "Monthly update for #{name}."
              r.autofill_completed = true
              r.enable_portco_upload = true
            end
            
            # Add some KPIs to these monthly reports for Query 36 (missed budget)
            # We'll make CyberShield miss its budget for 3 consecutive months
            mrr_val = 200_000
            mrr_val = 180_000 if type == "Actual" && name == "CyberShield"
            mrr_val = 210_000 if type == "Budget" && name == "CyberShield"

            report = KpiReport.find_by(portfolio_company_id: portco.id, as_of: month_as_of, period: "Month", tag_list: type)
            
            Kpi.find_or_create_by!(
              kpi_report_id: report.id,
              portfolio_company_id: portco.id,
              entity_id: entity_id,
              name: "MRR"
            ) do |k|
              k.investor_kpi_mapping_id = mappings["MRR"]&.id
              k.value = mrr_val
              k.status = "approved"
            end
          end
        end
      end
    end
  end
end

puts "Success: Unified KPI data generation complete!"
