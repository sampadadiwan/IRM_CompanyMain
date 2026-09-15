# Steps for features/fund/ag_grid_date_locale.feature — asserts AG Grid date
# cells render in the locale WithLocale resolved from the Accept-Language
# header, i.e. the same format Rails uses for server-rendered dates.
#
# "my browser sends an Accept-Language header of" and "I visit the Portfolio
# Investments AG Grid page" are reused from ransack_filter_date_locale_steps.rb
# and ag_grid_health_steps.rb respectively.

# Scope to .ag-center-cols-container: pinned columns render a second .ag-row for
# the same record. Skip .ag-row-footer too: BaseAgGrid sets
# groupIncludeTotalFooter (base_ag_grid.js), so every grid renders a grand-total
# footer row in the same container, whose date cell is empty.
def ag_data_cells(col_id)
  ".ag-center-cols-container .ag-row:not(.ag-row-footer) [col-id='#{col_id}']"
end

Then('the grid {string} cell should read {string}') do |col_id, expected|
  expect(page).to have_selector(
    ag_data_cells(col_id), text: expected, wait: 15
  ), "no #{col_id} cell reading #{expected.inspect}; " \
     "cells present: #{all(ag_data_cells(col_id)).map(&:text).inspect}"
end

Then('the page should publish the date format {string}') do |expected|
  published = page.evaluate_script(
    "document.querySelector('meta[name=\"app-date-format\"]')?.content"
  )
  expect(published).to eq(expected)
end

Then('the grid {string} cell should match the published date format') do |col_id|
  expect(page).to have_selector(ag_data_cells(col_id), wait: 15)

  format = page.evaluate_script(
    "document.querySelector('meta[name=\"app-date-format\"]')?.content"
  )
  expect(format).to be_present, "layout published no app-date-format meta tag"

  # Turn the strftime pattern into a matcher so this stays honest if the
  # locale's date.formats.default is ever changed.
  pattern = Regexp.escape(format)
                  .gsub("%d", '\d{2}')
                  .gsub("%m", '\d{2}')
                  .gsub("%Y", '\d{4}')

  cells = all(ag_data_cells(col_id)).map(&:text).reject(&:empty?)
  expect(cells).not_to be_empty, "no populated #{col_id} cells in the grid"
  cells.each do |cell|
    expect(cell).to match(/\A#{pattern}\z/),
                    "grid cell #{cell.inspect} does not match published format #{format.inspect}"
  end
end
