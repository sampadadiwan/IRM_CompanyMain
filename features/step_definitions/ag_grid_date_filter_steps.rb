# Steps for features/fund/ag_grid_date_filter.feature
#
# Reused, do not redefine:
#   "I visit the Portfolio Investments AG Grid page" — ag_grid_health_steps.rb
#   "the AG grid should boot and render rows"        — ag_grid_health_steps.rb
#   "the grid {string} cell should read {string}"    — ag_grid_date_locale_steps.rb
#   "my browser sends an Accept-Language header of {string}"
#                                                    — ransack_filter_date_locale_steps.rb
# `ag_data_cells(col_id)` is also defined in ag_grid_date_locale_steps.rb; it scopes to
# .ag-center-cols-container and skips .ag-row-footer (the grand-total row BaseAgGrid
# adds via groupIncludeTotalFooter, whose date cell is empty).

# The filter body rendered by custom/ag_locale_date_filter.js.
LOCALE_DATE_FILTER       = ".ag-locale-date-filter".freeze
LOCALE_DATE_FILTER_INPUT = "#{LOCALE_DATE_FILTER} input.ag-input-field-input".freeze

# NOTE: this is the only place in the suite that drives an ag-Grid column menu, so it
# is the only step coupled to ag-Grid's own popup DOM (.ag-header-cell-menu-button,
# .ag-menu, .ag-tab). If an ag-Grid upgrade moves that markup, fix it here — the
# failure will look like "the date filter broke" but will not be about dates at all.
When('I open the {string} column filter') do |col_id|
  header = find(".ag-header-cell[col-id='#{col_id}']")
  # The menu button is opacity:0 until the header is hovered.
  header.hover
  header.find(".ag-header-cell-menu-button").click
  expect(page).to have_selector(".ag-menu", wait: 10)

  # ag-Grid 30's TABS_DEFAULT is [general, filter, columns], so the menu opens on the
  # General tab and the Filter tab has to be selected. Tabs carry an aria-label; fall
  # back to position if that label is ever localised away.
  unless page.has_selector?(LOCALE_DATE_FILTER, wait: 1)
    tabs = all(".ag-menu .ag-tab")
    filter_tab = tabs.find { |tab| tab[:"aria-label"].to_s.match?(/filter/i) } || tabs[1]
    expect(filter_tab).not_to be_nil,
                              "no Filter tab in the #{col_id} column menu; " \
                              "tabs found: #{tabs.map { |t| t[:'aria-label'] }.inspect}"
    filter_tab.click
  end

  expect(page).to have_selector(LOCALE_DATE_FILTER_INPUT, wait: 10),
                  "the #{col_id} filter is not the locale date filter — ag-Grid fell " \
                  "back to its own <input type=\"date\">, which cannot be typed into"
end

When('I type {string} into the column filter') do |value|
  # A real per-keystroke type: the component applies the filter from its `input`
  # handler, so setting .value directly would prove nothing.
  find(LOCALE_DATE_FILTER_INPUT).set(value)
end

When('I leave the column filter') do
  # Dispatch blur rather than clicking away: clicking outside closes the ag-Grid popup
  # and takes the element being asserted on with it.
  page.execute_script(
    "document.querySelector(#{LOCALE_DATE_FILTER_INPUT.to_json})" \
    ".dispatchEvent(new Event('blur'))"
  )
end

Then('the column filter should be marked invalid') do
  expect(page).to have_selector("#{LOCALE_DATE_FILTER} input.ag-locale-date-filter-invalid", wait: 5)
end

Then('the grid should have no {string} cell reading {string}') do |col_id, unexpected|
  expect(page).to have_no_selector(
    ag_data_cells(col_id), text: unexpected, wait: 10
  ), "#{col_id} cell reading #{unexpected.inspect} is still in the grid; " \
     "cells present: #{all(ag_data_cells(col_id)).map(&:text).inspect}"
end
