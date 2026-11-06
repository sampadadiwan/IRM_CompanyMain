# Direct-request (rack_test) steps for features/security/compliance_tenant_isolation.feature
# Each sends the request a tampered form or URL would send, as the signed-in user.

Given('Delta Partners with a company admin {string} and a fund {string}') do |name, fund_name|
  delta = cmp_entity!("Delta Partners")
  cmp_user!(delta, name, admin: true)
  fund = cmp_fund!(delta, fund_name, category: "Category II", start_date: Date.new(2025, 1, 1))
  inv = cmp_investor!(delta, "Delta LP", category: "LP")
  cmp_commit!(fund, inv, cr(50))
end

Given('an investor user {string} in Growth Fund I') do |name|
  investor_entity = cmp_entity!("Lata Family Office", type: "Investor")
  user = FactoryBot.create(:user, entity: investor_entity, first_name: name, last_name: "Test", email: "#{name.downcase}@investor.example")
  cmp[:users][name] = User.find(user.id)
end

# E138 — GP staff can hold the investor role too; what counts is the role they act in (curr_role)
Given('{string} also holds the investor role') do |name|
  user = cmp_user(name)
  user.add_role(:investor)
  expect(user.reload.curr_role).to eq("employee")
end

Given('{string} is acting as an investor') do |name|
  cmp_user(name).update_column(:curr_role, "investor")
end

Given('I am signed in to compliance as {string}') do |name|
  @me = User.find(cmp_user(name).id)
  Warden.test_mode!
  login_as(@me, scope: :user)
  visit("/")
end

def cmp_submit(method, path, params = {})
  page.driver.submit method, path, params
end

Then('the compliance request is denied') do
  denied = page.has_text?("Access Denied", wait: 2) || page.status_code.in?([403, 404]) || page.has_text?("The page you were looking for doesn't exist", wait: 0)
  expect(denied).to be true
end

Then('the compliance page shows {string}') do |text|
  expect(page).to have_text(text)
end

Then('the compliance page does not show {string}') do |text|
  expect(page).not_to have_text(text)
end

When('I request a test run of the SEBI pack on {string}') do |fund_name|
  cmp_submit :post, test_run_compliance_pack_version_path(cmp[:sebi]), { fund_id: cmp_fund(fund_name).id }
end

When('I open the compliance packs list') do
  visit compliance_packs_path
end

When('I open the Horizon fund agreement pack by URL') do
  visit compliance_pack_path(cmp[:fa])
end

When('I send an edit of the SEBI pack setting the concentration limit to {int}') do |value|
  defn = cmp[:sebi].definition_hash
  defn["checks"].each { |c| c["limit"]["value"] = value if c["key"] == "sebi_concentration_cat12" }
  cmp_submit :patch, compliance_pack_version_path(cmp[:sebi]), { compliance_pack_version: { definition: defn.to_json } }
end

Then('the SEBI concentration limit is still {int}') do |value|
  expect(cmp[:sebi].reload.check("sebi_concentration_cat12").dig("limit", "value")).to eq(value)
end

Given('{string} has a pending override of {string} on {string} at {int}') do |user, check, fund_name, value|
  submit = ComplianceRequestSubmit.call(user: cmp_user(user), kind: "override", target: cmp_fund_pack(fund_name),
                                        check_key: cmp_check_key(check, fund_name), reason: "Board policy 2026-07", payload: { "limit" => value })
  expect(submit.error).to be_nil
end

When('I approve the latest compliance request') do
  visit compliance_home_path
  cmp_submit :patch, approve_compliance_request_path(ComplianceRequest.order(:id).last)
end

Then('the latest compliance request is still {string}') do |status|
  expect(ComplianceRequest.order(:id).last.status).to eq(status)
end

When('I attach {string} to {string} by a direct request') do |pack_name, fund_name|
  visit compliance_home_path
  cmp_submit :post, fund_compliance_packs_path, { fund_compliance_pack: { fund_id: cmp_fund(fund_name).id, compliance_pack_id: CompliancePack.find_by!(name: pack_name).id, classification: "Category II" } }
end

Then('{string} carries no {string}') do |fund_name, pack_name|
  expect(FundCompliancePack.joins(:compliance_pack).where(fund_id: cmp_fund(fund_name).id, compliance_packs: { name: pack_name })).to be_none
end

Given('the fund agreement concentration on {string} has an open item') do |fund_name|
  fund = cmp_fund(fund_name)
  inv = cmp_investor!(horizon, "GIFT LP", category: "LP")
  cmp_commit!(fund, inv, cr(100))
  cmp_invest!(fund, "GIFT Investee", cr(60))
  setup = cmp_setup
  setup.set_fund_figure("est_expenses", fund, cr(10))
  setup.save!
  cmp_run!(fund_name, "2026-11-05")
  @gift_item = ComplianceRegisterItem.open_items.find_by!(fund_id: fund.id, check_key: "fa_concentration")
end

When('I open the compliance register') do
  # The page holds lazy tabs; then load the All tab's grid as Turbo would, so assertions see the rows
  visit compliance_register_items_path(status: "all")
  @register_page_html = page.html
  cmp_frame_visit("register_all_frame", compliance_register_items_path(status: "all"))
end

When('I open the GIFT register item by URL') do
  visit compliance_register_item_path(@gift_item)
end

When('I open a Horizon register item by URL') do
  visit compliance_register_item_path(ComplianceRegisterItem.where(entity_id: horizon.id).first)
end

When('I open the compliance setup') do
  visit compliance_entity_setup_path
end

When('I open the compliance home') do
  visit compliance_home_path
end

Then('Lata has no Compliance menu entry') do
  expect(ComplianceAccess.viewer?(cmp_user("Lata"))).to be false
end

When('I mark the {string} duty done by a direct request') do |name|
  cmp_submit :patch, complete_compliance_duty_path(cmp_duty(name)), { note: "done" }
end

Then('{string} got no compliance notices') do |name|
  user = cmp_user(name)
  expect(Noticed::Notification.where(recipient_type: "User", recipient_id: user.id).joins(:event).where(noticed_events: { type: "ComplianceNotifier" })).to be_none
end

When('I export the compliance register for November 2026') do
  cmp_submit :post, compliance_exports_path, { from: "2026-11-01", to: "2026-11-30" }
end

When('I request an override of {string} to {int} by a direct request') do |check, value|
  @requests_before = ComplianceRequest.count
  visit compliance_home_path
  cmp_submit :post, compliance_requests_path, { compliance_request: { kind: "override", target_type: "FundCompliancePack",
                                                                      target_id: cmp_fund_pack("Horizon Growth Fund I").id,
                                                                      check_key: cmp_check_key(check), reason: "Board policy 2026-07",
                                                                      payload: { limit: value } } }
end

Then('no compliance request was created') do
  expect(ComplianceRequest.count).to eq(@requests_before)
end

When('I open the Growth Fund I preview of SEBI v2 by URL') do
  visit preview_fund_compliance_pack_path(cmp_fund_pack("Horizon Growth Fund I"), version_id: cmp[:v2].id)
end

When('I request a re-run of {string} for {string}') do |fund_name, _date|
  cmp_submit :post, rerun_fund_compliance_pack_path(cmp_fund_pack(fund_name))
end

When('I request deletion of the latest Growth Fund I result') do
  @result = cmp_latest("Horizon Growth Fund I", "sebi_concentration_cat12")
  cmp_submit :delete, compliance_result_path(@result)
end

Then('the latest Growth Fund I result still exists') do
  expect(ComplianceResult.exists?(@result.id)).to be true
end
