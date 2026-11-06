# Steps for features/compliance/compliance_screens.feature and X69 (rack_test).
# Lazy tab frames are requested the way Turbo does: the frame URL with a Turbo-Frame header.

def cmp_frame_visit(frame, path)
  page.driver.header("Turbo-Frame", frame)
  visit path
ensure
  page.driver.header("Turbo-Frame", nil)
end

def cmp_stream_submit(method, path, params = {})
  page.driver.header("Accept", "text/vnd.turbo-stream.html")
  page.driver.submit method, path, params
ensure
  page.driver.header("Accept", nil)
end

# ── E139 register filter and tabs ────────────────────────────────────────────────────────────
Given('Horizon also has a fund {string} with a closed register item') do |fund_name|
  fund = cmp_fund!(horizon, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  fp = cmp_attach!(fund, cmp[:sebi].compliance_pack, "Category II")
  ComplianceRegisterItem.create!(entity: horizon, fund:, fund_compliance_pack: fp, check_key: "sebi_investor_count", status: "closed",
                                 closed_reason: "cleared", opened_on: Date.new(2026, 10, 1), closed_on: Date.new(2026, 10, 5), fix_by: Date.new(2026, 10, 31))
end

When('I open the register tab {string}') do |tab|
  cmp_frame_visit("register_#{tab}_frame", compliance_register_items_path(status: tab))
end

When('I filter the register frame by status {string} and fund {string}') do |status, fund_name|
  cmp_frame_visit("register_filtered_frame", compliance_register_items_path(status: "open", q: { status_eq: status, fund_name_eq: fund_name }))
end

When('I open the register page filtered by status {string}') do |status|
  visit compliance_register_items_path(q: { status_eq: status })
end

Then('the register grid lists {int} item(s)') do |count|
  expect(page.all("table#compliance_register_items tbody tr").size).to eq(count)
end

Then('the register card {string} shows {int}') do |label, count|
  expect(find("#register_grid_stats")).to have_text(/#{count}\s*#{Regexp.escape(label)}/)
end

Then('the register shows only the {string} tab') do |label|
  expect(page.all("#register_tabs .nav-link").map { |l| l.text.strip }).to eq([label])
end

# ── E143 lazy tabs ───────────────────────────────────────────────────────────────────────────
Then('the tab {string} loads lazily') do |frame|
  html = frame.start_with?("register_") && @register_page_html ? Capybara.string(@register_page_html) : page
  expect(html).to have_css("turbo-frame##{frame}[loading='lazy'][src]")
end

When('I open the SEBI version page') do
  visit compliance_pack_version_path(cmp_fund_pack("Horizon Growth Fund I").compliance_pack_version)
end

When('I open the {string} tab of the SEBI version') do |pane|
  version = cmp_fund_pack("Horizon Growth Fund I").compliance_pack_version
  cmp_frame_visit("version_#{pane}_pane", compliance_pack_version_path(version, pane:))
end

When('I open the Growth Fund I SEBI dashboard') do
  visit fund_compliance_pack_path(cmp_fund_pack("Horizon Growth Fund I"))
end

Then('the SEBI results tab loads lazily') do
  expect(page).to have_css("turbo-frame#pack_#{cmp_fund_pack('Horizon Growth Fund I').id}_results[loading='lazy'][src]")
end

When('I open the SEBI results tab of Growth Fund I') do
  fp = cmp_fund_pack("Horizon Growth Fund I")
  cmp_frame_visit("pack_#{fp.id}_results", fund_compliance_pack_path(fp, pane: "results"))
end

# ── E140 Turbo streams ───────────────────────────────────────────────────────────────────────
When('I assign the {string} item to {string} as a Turbo stream') do |check, user|
  cmp_stream_submit :patch, assign_compliance_register_item_path(cmp_item(check)), { assignee_id: cmp_user(user).id }
end

When('I request an explanation of the {string} item as a Turbo stream') do |check|
  item = cmp_item(check)
  cmp_stream_submit :post, compliance_requests_path, { compliance_request: { kind: "explanation", target_type: "ComplianceRegisterItem", target_id: item.id,
                                                                             reason: "Exit of Acme agreed for Q4", payload: { text: "Temporary" } } }
end

When('I approve the explanation of the {string} item as a Turbo stream') do |check|
  cmp_stream_submit :patch, approve_compliance_request_path(cmp_item(check).pending_explanation)
end

Then('the Turbo stream replaces the {string} item') do |check|
  expect(page.body).to include(%(<turbo-stream action="replace" target="compliance_register_item_#{cmp_item(check).id}">))
  expect(page.body).to include(%(<turbo-stream action="update" target="user_alert">))
end

When('I mark the {string} duty done as a Turbo stream') do |name|
  cmp_stream_submit :patch, complete_compliance_duty_path(cmp_duty(name)), { note: "Filed", evidence: cmp_evidence_file }
end

Then('the Turbo stream replaces the {string} duty row') do |name|
  expect(page.body).to include(%(<turbo-stream action="replace" target="compliance_duty_#{cmp_duty(name).id}">))
  expect(page.body).to include(%(<turbo-stream action="replace" target="duties_grid_stats">))
end

When('I confirm the facts of the IC note of {string} as a Turbo stream') do |company|
  cmp_stream_submit :patch, confirm_document_reading_path(cmp_ic_reading(company)), {}
end

Then('the Turbo stream replaces the facts of the IC note of {string}') do |company|
  expect(page.body).to include(%(<turbo-stream action="replace" target="document_reading_#{cmp_ic_reading(company).id}">))
end

When('I run {string} now as a Turbo stream') do |fund_name|
  cmp_stream_submit :post, run_now_fund_compliance_pack_path(cmp_fund_pack(fund_name))
end

Then('the Turbo stream shows the flash {string}') do |text|
  expect(page.body).to include(%(<turbo-stream action="update" target="user_alert">))
  expect(page.body).to include(text)
end

# ── E141 / E142 explained working ────────────────────────────────────────────────────────────
When('I open the latest {string} result of {string}') do |check, fund_name|
  visit compliance_result_path(cmp_latest(fund_name, cmp_check_key(check, fund_name)))
end

Then('the result verdict says {string}') do |text|
  expect(find_by_id("result_verdict")).to have_text(text)
end

Then('the result steps include {string} = {string}') do |label, value|
  row = page.all("#result_steps li").detect { |li| li.find(".step-label").text.strip.start_with?(label) }
  expect(row).to be_present, "no step #{label}"
  expect(row.find(".step-value")).to have_text(value)
end

Then('the result remedy says reduce to {string} by {string} or raise to {string}') do |to, by, raise_to|
  remedy = find_by_id("result_remedy")
  [to, by, raise_to].each { |v| expect(remedy).to have_text(v) }
end

Then('the result lists the largest investees') do
  expect(page.all("#result_others tbody tr").size).to be >= 2
end

# ── X69 entity without Compliance ────────────────────────────────────────────────────────────
Given('Horizon has Compliance switched off') do
  horizon.permissions.unset(:enable_compliance)
  horizon.save!
end

Then('{string} has no Compliance menu entry') do |name|
  expect(ComplianceAccess.viewer?(User.find(cmp_user(name).id))).to be false
end

Then('the fund page of {string} has no Compliance tab') do |fund_name|
  visit fund_path(cmp_fund(fund_name))
  expect(page).to have_no_css("#compliance_tab")
  expect(page).to have_no_css("turbo-frame#fund_compliance_tab")
end

Then('{string} has no compliance runs') do |fund_name|
  expect(ComplianceRun.where(fund_id: cmp_fund(fund_name).id)).to be_none
end

Then('no result step restates its own value') do
  page.all("#result_steps li").to_a.each do |li|
    calc = li.all(".step-calc").first&.text.to_s.strip
    value = li.find(".step-value").text.strip
    expect(calc).not_to eq(value), "step restates its value: #{li.text}"
  end
end

# ── E203 one funds grid (R175) ───────────────────────────────────────────────────────────────
Then('the funds grid row {string} shows {string}') do |fund_name, text|
  expect(find("#compliance_funds #fund_#{cmp_fund(fund_name).id}")).to have_text(text)
end

Then('the funds grid row {string} has an Attach button') do |fund_name|
  expect(page).to have_css("#attach_fund_#{cmp_fund(fund_name).id}")
end

# The row's Attach opens the form in the remote_modal frame; rack_test requests it as Turbo does
When('I open the attach form from the {string} row') do |fund_name|
  path = find("#attach_fund_#{cmp_fund(fund_name).id}")[:href]
  cmp_frame_visit("remote_modal", path)
end

Then('the attach form has {string} chosen') do |fund_name|
  expect(page).to have_select("fund_compliance_pack[fund_id]", selected: fund_name)
end

When('I attach {string} as {string} from the attach form') do |pack_name, classification|
  select pack_name, from: "fund_compliance_pack[compliance_pack_id]"
  fill_in "fund_compliance_pack[classification]", with: classification
  find_by_id("attach_pack_submit").click
end

Then('the funds grid row {string} shows {string} under {string}') do |fund_name, text, pack_name|
  pack = CompliancePack.find_by!(name: pack_name)
  expect(page).to have_css("#fund_#{cmp_fund(fund_name).id}_pack_#{pack.id}", text:)
end

When('I open the old fund packs page') do
  visit fund_compliance_packs_path
end

Then('I am on the compliance funds grid') do
  expect(page).to have_current_path(compliance_home_path, ignore_query: true)
  expect(page).to have_css("#compliance_funds")
end
