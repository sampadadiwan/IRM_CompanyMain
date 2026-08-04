# Steps that verify the AG Grid CDN assets (JS + core CSS + quartz theme CSS)
# not only load but are actually applied to the rendered grid.
# They are designed to fail when the CSS <link> pins in the layouts drift out
# of sync with the AG Grid JS version (e.g. a pinned version where
# ag-theme-quartz.css does not exist and the CDN returns 404).

When("I visit the Portfolio Investments AG Grid page") do
  # ?ag=true switches the index view from the plain HTML table to the AG Grid
  visit portfolio_investments_path(ag: true)
end

Then("the AG grid should boot and render rows") do
  # .ag-root-wrapper only exists once the AG Grid JS has initialised the grid
  expect(page).to have_selector(".ag-root-wrapper", wait: 15)
  # Header cells prove the column defs were consumed
  expect(page).to have_selector(".ag-header-cell", minimum: 1, wait: 15)
  # Rows prove the data-source JSON round-trip worked
  expect(page).to have_selector(".ag-center-cols-container .ag-row", minimum: 1, wait: 15)
end

Then("every AG grid stylesheet on the page should have loaded") do
  # A <link rel="stylesheet"> that fails to load (404, wrong content-type…)
  # keeps a null .sheet property — exactly what happens when the CDN pin
  # points at a version where the file does not exist.
  links = page.evaluate_script(<<~JS)
    Array.from(document.querySelectorAll('link[rel="stylesheet"][href*="ag-grid"]'))
         .map(l => ({ href: l.href, loaded: l.sheet !== null }))
  JS

  # The layout must include at least the core CSS and one theme CSS;
  # zero links would mean the grid styling was silently dropped from the layout
  expect(links.length).to be >= 2

  failed = links.reject { |l| l["loaded"] }
  expect(failed).to be_empty,
                   "AG grid stylesheets failed to load: #{failed.map { |l| l['href'] }.join(', ')}"
end

Then("the AG grid structural CSS should be applied") do
  # ag-grid.css (the core structural sheet) sets .ag-root-wrapper to flex;
  # without it the wrapper falls back to the browser default of block
  display = page.evaluate_script(
    "getComputedStyle(document.querySelector('.ag-root-wrapper')).display"
  )
  expect(display).to eq("flex"),
                     "core ag-grid.css not applied (.ag-root-wrapper display=#{display})"
end

Then("the AG grid quartz theme CSS should be applied") do
  # The quartz theme defines its parameters as CSS custom properties on the
  # .ag-theme-quartz element; if the theme CSS is missing or is a version
  # that doesn't ship quartz, the variable resolves to an empty string
  active_color = page.evaluate_script(<<~JS)
    getComputedStyle(document.querySelector('.ag-theme-quartz, .ag-theme-quartz-dark'))
      .getPropertyValue('--ag-active-color').trim()
  JS
  expect(active_color).not_to be_empty,
                              "quartz theme CSS not applied: --ag-active-color is empty"
end

Then("the AG grid icons should use the AG icon font") do
  # Header/menu icons are glyphs from the agGridQuartz webfont declared in the
  # theme CSS; when the theme CSS is missing the icons render as empty boxes
  # (the exact symptom of the broken-pin regression this feature guards against)
  font = page.evaluate_script(<<~JS)
    (() => {
      const icon = document.querySelector('.ag-icon');
      return icon ? getComputedStyle(icon).fontFamily : null;
    })()
  JS
  expect(font).not_to be_nil, "no .ag-icon element found in the grid"
  expect(font).to include("agGrid"),
                  "AG icon font not applied (.ag-icon font-family=#{font})"
end
