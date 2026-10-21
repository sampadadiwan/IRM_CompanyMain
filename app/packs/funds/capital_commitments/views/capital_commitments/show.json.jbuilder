json.partial! "capital_commitments/capital_commitment", capital_commitment: @capital_commitment

# The LP fund page's optional sections, as the GP has switched them on for this fund (the website's
# funds/_investor_fund_details shows each only when its feature is on) — the LP mobile app's Fund screen
fund = @capital_commitment.fund
json.lp_sections do
  json.units fund.features.show_fund_units?
  json.ratios fund.features.show_fund_ratios?
  json.portfolio fund.features.show_portfolios?
end
# A feeder with no fund-level ratios of its own shows its master fund's (Fund#lp_ratios_fund)
json.ratios_fund_id fund.lp_ratios_fund_id
json.ratios_from_master fund.lp_ratios_from_master?
