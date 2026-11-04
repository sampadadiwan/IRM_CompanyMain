# Steps for features/fund/portfolio_investments_widget_group_by.feature (fix-portfolio-dashboard-widgets: Group by column).
# Worked examples: openspec/changes/fix-portfolio-dashboard-widgets/design.md#worked-examples

Then('the field {string} should be a list including {string}') do |key, option|
  field = find_field("metadata_#{key}")
  expect(field.tag_name).to eq("select")
  expect(field).to have_css("option", text: option)
end

Then('the Portfolio Investments widget should request the AG grid grouped by {string}') do |column|
  expect(page).to have_css("turbo-frame#portfolio_investments_frame[src*='group_by_column=#{column}']", visible: :all)
  expect(page).to have_no_css("turbo-frame#aggregate_portfolio_investments_frame", visible: :all)
end

Then('the Portfolio Investments widget should request the aggregate table') do
  expect(page).to have_css("turbo-frame#aggregate_portfolio_investments_frame", visible: :all)
  expect(page).to have_no_css("turbo-frame#portfolio_investments_frame", visible: :all)
end
