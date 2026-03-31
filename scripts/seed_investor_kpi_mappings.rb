require 'factory_bot_rails'

entity_id = 157
standard_kpis = [
  { name: "Revenue", category: "Income Statement", data_type: "money" },
  { name: "COGS", category: "Income Statement", data_type: "money" },
  { name: "Gross Profit", category: "Income Statement", data_type: "money" },
  { name: "Operating Expenses", category: "Income Statement", data_type: "money" },
  { name: "EBITDA", category: "Income Statement", data_type: "money" },
  { name: "Net Income", category: "Income Statement", data_type: "money" },
  { name: "MRR", category: "Operational Metrics", data_type: "money" },
  { name: "Cash Burn", category: "Cashflow Statement", data_type: "money" },
  { name: "CAC", category: "Operational Metrics", data_type: "money" },
  { name: "LTV", category: "Operational Metrics", data_type: "money" },
  { name: "Marketing Spend", category: "Income Statement", data_type: "money" }
]

Chewy.strategy(:atomic) do
  # Find all portfolio companies for this entity
  # Using the category we assigned earlier
  portcos = Investor.where(entity_id: entity_id, category: "Portfolio Company")
  
  puts "Found #{portcos.count} portfolio companies to seed mappings for."

  portcos.each do |portco|
    puts "Seeding mappings for #{portco.investor_name}..."
    
    standard_kpis.each_with_index do |kpi_data, index|
      mapping = InvestorKpiMapping.find_or_create_by!(
        entity_id: entity_id,
        investor_id: portco.id,
        standard_kpi_name: kpi_data[:name]
      ) do |ikm|
        ikm.reported_kpi_name = kpi_data[:name]
        ikm.category = kpi_data[:category]
        ikm.data_type = kpi_data[:data_type]
        ikm.show_in_report = true
        ikm.position = index + 1
      end
      
      # For the existing reports, if they don't have these KPIs, we could create them.
      # But the user just asked to seed the mappings.
    end
  end
end

puts "Done seeding InvestorKpiMappings!"
