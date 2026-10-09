# Steps for the `datatable` Stimulus controller. These run under rack_test (no browser, no JS), so
# they check what Stimulus needs in order to attach the controller — the data-controller markup
# and the importmap pin — and the source of the script actually served, not its runtime behaviour.

Given('I am on the favorites page') do
  visit(favorites_path)
  expect(page).to have_css("table.jqDataTable")
end

Then('the data table is inside a {string} controller') do |identifier|
  expect(page).to have_css("[data-controller~='#{identifier}'] table.jqDataTable")
end

Then('the table column {string} is present') do |header|
  expect(page).to have_css("table.jqDataTable thead th", text: header)
end

# eagerLoadControllersFrom("controllers") registers every importmap pin under controllers/, so a
# pin for controllers/<identifier>_controller is what makes data-controller="<identifier>" attach.
Then('the importmap pins the {string} Stimulus controller') do |identifier|
  @controller_url = importmap_imports["controllers/#{identifier}_controller"]
  expect(@controller_url).to be_present
end

Then('the {string} controller source installs the responsive zoom patch') do |identifier|
  expect(controller_source(identifier)).to include("patchResponsiveZoomTolerance")
end

# Responsive 3's s.columns is a DataTables Api instance: it has map but no forEach, so array
# methods on it throw at a fractional devicePixelRatio.
Then('the {string} controller source does not call array methods on the responsive columns') do |identifier|
  offending = controller_source(identifier).lines.each_with_index
                                           .select { |line, _| line.match?(/\bcolumns\.(forEach|map)\(/) }
                                           .map { |line, i| "#{i + 1}: #{line.strip}" }
  expect(offending).to be_empty
end

def importmap_imports
  JSON.parse(find("script[type='importmap']", visible: false).text(:all))["imports"]
end

# Read the source rather than the URL the importmap serves: when public/assets holds a
# precompiled build, Rails serves that instead, which may not match the code under test.
def controller_source(identifier)
  Rails.root.join("app/javascript/controllers/#{identifier}_controller.js").read
end
