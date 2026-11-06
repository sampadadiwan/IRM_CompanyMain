# Steps for features/compliance/compliance_guidance.feature — Phase 5 newcomer guidance, check
# descriptions and "How we checked" (business-rules group 13). rack_test throughout.

GS_KEYS = { "owner" => "owner", "attach" => "attach", "inputs" => "inputs", "lists" => "lists", "first run" => "first_run",
            "recipients" => "recipients", "monitoring" => "monitoring", "owned" => "owned" }.freeze

# ── A firm that has just switched Compliance on ─────────────────────────────────────────────
Given('a new firm {string} with Compliance switched on, owner {string} and approver {string}') do |firm, owner, approver|
  cmp_sebi_pack!
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("2026-11-04 10:00")) do
    entity = cmp_entity!(firm)
    cmp_user!(entity, owner, admin: true)
    cmp_user!(entity, approver, approve: true)
    fund = cmp_fund!(entity, "#{firm.split.first} Fund I", category: "Category II", start_date: Date.new(2025, 1, 1))
    sponsor = cmp_investor!(entity, "#{firm} Sponsor", category: "Sponsor")
    lp = cmp_investor!(entity, "#{firm} LP", category: "LP")
    cmp_commit!(fund, sponsor, cr(6))
    cmp_commit!(fund, lp, cr(94))
    cmp_invest!(fund, "#{firm} Investee", cr(20))
    setup = ComplianceEntitySetup.for(entity)
    setup.owner = cmp_user(owner)
    setup.save!
    cmp[:new_firm] = entity
  end
end

Given('a new firm {string} with Compliance switched on and one user {string}') do |firm, name|
  cmp_sebi_pack!
  entity = cmp_entity!(firm)
  cmp_user!(entity, name, admin: true)
  setup = ComplianceEntitySetup.for(entity)
  setup.owner = cmp_user(name)
  setup.save!
  cmp[:new_firm] = entity
end

Given('a firm {string} without the Compliance flag sets up compliance') do |firm|
  travel_to(ActiveSupport::TimeZone[ComplianceWorld::IST].parse("2026-11-04 10:00")) do
    entity = FactoryBot.create(:entity, name: firm, entity_type: "Investment Fund", currency: "INR", units: "Crores")
    cmp_user!(entity, "Omar", admin: true)
    cmp[:new_firm] = entity
    setup = ComplianceEntitySetup.for(entity)
    setup.owner = cmp_user("Omar")
    setup.save!
  end
end

def cmp_new_firm_fund
  Fund.where(entity_id: cmp[:new_firm].id).order(:id).first
end

When('{string} attaches SEBI to the new firm\'s fund') do |_user|
  cmp_attach!(cmp_new_firm_fund, cmp[:sebi].compliance_pack, "Category II")
end

When('the new firm maps its inputs') do
  setup = ComplianceEntitySetup.for(cmp[:new_firm])
  setup.set_mapping("sponsor", { "categories" => ["Sponsor"] })
  setup.set_fund_figure("est_expenses", cmp_new_firm_fund, cr(5))
  setup.save!
end

When('{string} turns monitoring on for the new firm') do |user|
  @setup_result = ComplianceSetupUpdate.call(setup: ComplianceEntitySetup.for(cmp[:new_firm]),
                                             params: ActionController::Parameters.new(monitoring_enabled: "1"), user: cmp_user(user))
end

# ── Getting started ─────────────────────────────────────────────────────────────────────────
Then('Getting started shows {string}') do |text|
  expect(find_by_id("getting_started_count")).to have_text(text)
end

Then('Getting started step {string} is {string}') do |step, state|
  expect(find_by_id("gs_step_#{GS_KEYS.fetch(step)}", visible: :all)["data-step-state"]).to eq(state)
end

Then("What's needed now says {string}") do |text|
  expect(find_by_id("getting_started_message")).to have_text(text)
end

Then('Getting started says why {string}') do |text|
  expect(find_by_id("getting_started_why")).to have_text(text)
end

Then('the Getting started button reads {string}') do |text|
  expect(find_by_id("getting_started_action")).to have_text(text)
end

Then('Getting started has no button and says {string}') do |text|
  expect(page).to have_no_css("#getting_started_action")
  expect(find_by_id("getting_started_ask")).to have_text(text)
end

Then('Getting started notes {string}') do |text|
  expect(find_by_id("getting_started_note", visible: :all)).to have_text(text)
end

When('I press the Getting started button') do
  find_by_id("getting_started_action").click
end

Then('Getting started is complete') do
  expect(find_by_id("getting_started_complete")).to have_text("Setup complete · Show steps")
end

Given('Horizon has tagged {string} for the compliance digest') do |name|
  user = cmp_user(name)
  user.update!(tag_list: [user.tag_list.to_s, ComplianceNotices::TAG].compact_blank.join(","))
end

Given('every open Horizon item is assigned to {string}') do |name|
  ComplianceRegisterItem.open_items.where(entity_id: horizon.id).find_each { |i| i.update!(assignee: cmp_user(name), status: "in_progress") }
end

Given('Horizon attaches a pack needing the unmapped input {string}') do |label|
  definition = cmp_described({
                               "currency" => "INR", "period_basis" => "calendar", "classifications" => ["All funds"],
                               "inputs" => [{ "key" => "board_cap", "type" => "fund_figure", "label" => label }],
                               "measures" => [{ "key" => "board_cap", "label" => label, "op" => "input", "input" => "board_cap" }],
                               "checks" => [{ "key" => "board_cap_check", "name" => "Board cap", "kind" => "limit", "applies_to" => "all", "figure" => "board_cap",
                                              "compare" => "lte", "limit" => { "value" => 10, "unit" => "amount" }, "citation" => "LPA cl. 1" }],
                               "duties" => []
                             })
  pack = cmp_entity_pack!(horizon, "Horizon — board rules", definition)
  cmp_attach!(cmp_fund("Horizon Growth Fund I"), pack, "All funds")
end

# ── What's next, timing, section bar, tooltips, guide ───────────────────────────────────────
Then("What's next says {string}") do |text|
  expect(find_by_id("whats_next_message")).to have_text(text)
end

Then("What's next offers {string}") do |labels|
  labels.split(",").map(&:strip).each { |label| expect(find_by_id("whats_next_actions")).to have_text(label) }
end

Then("What's next offers no {string}") do |label|
  expect(page).to have_no_css("#whats_next_actions", text: label)
end

Then("What's next notes {string}") do |text|
  expect(find_by_id("whats_next_note")).to have_text(text)
end

Then('the timing banner says {string}') do |text|
  expect(find_by_id("timing_banner")).to have_text(text)
end

Then('the timing banner is amber') do
  expect(find_by_id("timing_banner")[:class]).to include("alert-warning")
end

Then('the page has the tooltip {string}') do |text|
  titles = page.all("[data-bs-title]", visible: :all).pluck("data-bs-title")
  expect(titles).to include(text)
end

Then('the section bar shows {string}') do |text|
  expect(find_by_id("compliance_section_bar").text.squish).to include(text)
end

Then('the section bar shows the open item count on Register') do
  count = ComplianceRegisterItem.open_items.where(entity_id: horizon.id).count
  expect(find_by_id("section_register").text.squish).to eq("Register #{count}")
end

Then('the guide icon opens the guide at {string}') do |anchor|
  expect(find_by_id("page_guide_icon")[:href]).to end_with("compliance_monitoring_user_guide##{anchor}")
end

When('I open the {string} register item of {string}') do |check, fund_name|
  visit compliance_register_item_path(cmp_item(check, fund_name))
end

# The register page itself (the shared "I open the compliance register" step ends on the All tab's frame)
When('I open the register page') do
  visit compliance_register_items_path
end

When('I open the Getting started frame') do
  visit compliance_getting_started_path
end

# ── About this check, How we checked ───────────────────────────────────────────────────────
Then('About this check says {string}') do |text|
  expect(find_by_id("about_this_check_text")).to have_text(text)
end

Then('How we checked says {string}') do |text|
  expect(find_by_id("how_we_checked_subtitle")).to have_text(text)
end

Then('the page shows {string} once') do |text|
  expect(page.text.scan(text).size).to eq(1)
end

Then('the earlier records link opens the investments before {string}') do |date|
  expect(find_by_id("result_earlier_link")[:href]).to include(CGI.escape("q[investment_date_lt]")).and include(date)
end

Given('a needs-review result of {string} on {string} with the summary {string}') do |check, fund_name, summary|
  fp = cmp_fund_pack(fund_name)
  run = ComplianceRun.create!(entity_id: fp.entity_id, fund_id: fp.fund_id, run_date: Date.new(2026, 11, 5), status: "succeeded", finished_at: Time.current)
  @result = ComplianceResult.create!(entity_id: fp.entity_id, fund_compliance_pack: fp, compliance_run: run, compliance_pack_version: fp.compliance_pack_version,
                                     check_key: cmp_check_key(check, fund_name), outcome: "needs_review", figure: 4, limit_value: 0,
                                     working: { "verdict" => summary, "message" => summary, "lines" => [summary], "checked" => 10, "ok" => 1,
                                                "failing_count" => 4,
                                                "failing_records" => [{ "label" => "Enter Pvt Ltd", "problem" => "Needs review — waiting to be read" }] })
end

When('I open that result') do
  visit compliance_result_path(@result)
end

Given("the sponsor's commitment to {string} is ₹{float} cr") do |fund_name, value|
  CapitalCommitment.where(fund_id: cmp_fund(fund_name).id, investor_id: cmp[:sponsor].id).find_each do |c|
    cents = (value.to_d * 10_000_000 * 100).round
    c.update_columns(committed_amount_cents: cents, folio_committed_amount_cents: cents)
  end
end

# ── Descriptions: publish gate, AI draft, backfill ─────────────────────────────────────────
Given('the fund agreement draft check {string} has no description') do |name|
  v = cmp_fa_draft
  d = v.definition_hash
  d["checks"].each { |c| c.delete("description") if c["name"] == name }
  v.update!(definition: d)
end

When('I open the Checks tab of the fund agreement draft') do
  cmp_frame_visit("version_checks_pane", compliance_pack_version_path(cmp_fa_draft, pane: "checks"))
end

When('Meera publishes the fund agreement draft') do
  @draft = cmp_fa_draft.reload
  @draft.mark_tested!(cmp_user("Meera"))
  @published = @draft.reload.publish!(user: cmp_user("Meera"), attrs: { effective_from: Date.new(2026, 12, 1), applicability: "all" })
end

When('I change the draft description to {string}') do |text|
  page.driver.submit :patch, compliance_check_draft_path(cmp_last_draft), { compliance_check_draft: { description: text } }
end

Then('the saved check {string} is described as {string}') do |name, text|
  check = cmp_fa_draft.reload.checks.detect { |c| c["name"] == name }
  expect(check["description"]).to eq(text)
end

Given('SEBI v1 was published before descriptions existed') do
  v = cmp[:sebi]
  @before_backfill = ComplianceDescriptionBackfill.without_descriptions(v.definition_hash)
  v.update_column(:definition, @before_backfill)
end

Given("SEBI v1's concentration limit was edited after loading") do
  v = cmp[:sebi]
  d = v.definition_hash
  d["checks"].each { |c| c["limit"]["value"] = 26 if c["key"] == "sebi_concentration_cat12" }
  v.update_column(:definition, d)
  @before_backfill = d
end

def cmp_backfill(execute)
  sources = { "SEBI — AIF" => Rails.root.glob("db/seeds/compliance/sebi_aif_*.json").map { |p| JSON.parse(File.read(p))["definition"] } }
  @audits_before = Audit.where(auditable_type: "CompliancePackVersion").count
  @backfill_lines = ComplianceDescriptionBackfill.call(sources:, execute:).map(&:to_s)
end

When('the description backfill runs as a dry run') do
  cmp_backfill(false)
end

When('the description backfill runs with EXECUTE=1') do
  cmp_backfill(true)
end

Then('the backfill reports {string}') do |text|
  expect(@backfill_lines).to include(text)
end

Then('SEBI v1 is unchanged') do
  expect(cmp[:sebi].reload.definition_hash).to eq(@before_backfill)
end

Then('every SEBI v1 check has its description and nothing else changed') do
  d = cmp[:sebi].reload.definition_hash
  expect(d["checks"].pluck("description").all?(&:present?)).to be(true)
  expect(ComplianceDescriptionBackfill.without_descriptions(d)).to eq(@before_backfill)
  expect(Audit.where(auditable_type: "CompliancePackVersion").count).to eq(@audits_before + 1)
end

# ── Notices and the super-admin list ───────────────────────────────────────────────────────
Then('{string} got the compliance notice {string} {int} time(s)') do |name, text, count|
  user = cmp_user(name)
  messages = Noticed::Event.where(type: "ComplianceNotifier").joins(:notifications)
                           .where(noticed_notifications: { recipient_type: "User", recipient_id: user.id }).map { |e| e.params[:message].to_s }
  expect(messages.count { |m| m.include?(text) }).to eq(count)
end

When('the new firm saves its setup again') do
  setup = ComplianceEntitySetup.for(cmp[:new_firm])
  setup.update!(time_zone: "Asia/Kolkata")
end

When('the hourly compliance tick happens {int} days after setup at 08:00 IST') do |days|
  at = ActiveSupport::TimeZone[ComplianceWorld::IST].parse("#{(Date.new(2026, 11, 4) + days).iso8601} 08:00")
  travel_to(at) { ComplianceScheduleJob.perform_now(now: at) }
end

Given('{string} is a CapHive super admin') do |name|
  caphive = cmp_entity!("CapHive Ops")
  user = cmp_user!(caphive, name, admin: true)
  # User#forbid_bad_role blocks add_role(:super) on purpose; the role is inserted directly, as
  # internal_docs_steps.rb does
  role = Role.find_or_create_by!(name: "super")
  ActiveRecord::Base.connection.execute("INSERT INTO users_roles (user_id, role_id) VALUES (#{user.id.to_i}, #{role.id.to_i})")
end

When('I open the customer setup list') do
  visit compliance_onboarding_path
end

# ── E198 duty cards follow the grid's filter ───────────────────────────────────────────────
Given('Horizon also carries SEBI on {string}') do |fund_name|
  cmp_attach!(cmp_fund(fund_name), cmp[:sebi].compliance_pack, "Category II")
end

When('I mark the {string} duty done from a grid filtered to {string}') do |name, fund_name|
  @grid_fund = fund_name
  cmp_stream_submit :patch, complete_compliance_duty_path(cmp_duty(name, fund_name)),
                    { note: "Filed", evidence: cmp_evidence_file, grid_q: { "fund_name_eq" => fund_name }.to_json }
end

# The "Overdue" card in the refreshed stats equals the filtered grid's overdue count, not the firm's
Then('the refreshed duty cards count only {string} duties') do |fund_name|
  doc = Nokogiri::HTML(page.body)
  stats = doc.at_css('turbo-stream[target="duties_grid_stats"] template')
  card = stats.css(".card-body").find { |c| c.at_css(".card-subtitle")&.text&.strip == "Overdue" }
  shown = card.at_css("h2, h3").text.strip.to_i
  today = Time.zone.today
  fp_ids = FundCompliancePack.where(fund_id: cmp_fund(fund_name).id).select(:id)
  filtered = ComplianceDuty.where(fund_compliance_pack_id: fp_ids, done_on: nil).where(due_on: ...today).count
  firm = ComplianceDuty.where(entity_id: horizon.id, done_on: nil).where(due_on: ...today).count
  expect(filtered).not_to eq(firm)
  expect(shown).to eq(filtered)
end

# ── E200: the section bar as lazy tabs on the Compliance hub (R170) ─────────────────────────
When('I open the compliance hub at the {string} tab') do |section|
  visit compliance_home_path(tab: ComplianceHub.pane_id(section.to_sym))
end

Then('the {string} section pill is active on the hub') do |section|
  pill = find_by_id("section_#{section}")
  expect(pill[:class]).to include("active")
  expect(pill[:'data-bs-toggle']).to eq("pill")
  expect(find_by_id(ComplianceHub.pane_id(section.to_sym), visible: :all)[:class]).to include("show active")
end

Then('the {string} pane is a lazy frame loading the register page') do |section|
  frame = find("turbo-frame##{ComplianceHub.frame_id(section.to_sym)}", visible: :all)
  expect(frame[:loading]).to eq("lazy")
  expect(frame[:src]).to eq(compliance_register_items_path)
  @hub_frame_src = frame[:src]
end

# What Turbo does when the pane becomes visible: GET the src with the Turbo-Frame header
When('the {string} pane\'s frame loads') do |section|
  page.driver.header("Turbo-Frame", ComplianceHub.frame_id(section.to_sym))
  visit @hub_frame_src
  page.driver.header("Turbo-Frame", nil)
end

Then('the frame answer holds the register inside the {string} hub frame, without a section bar') do |section|
  frame = find("turbo-frame##{ComplianceHub.frame_id(section.to_sym)}")
  expect(frame).to have_text("Compliance register")
  expect(frame).to have_css("turbo-frame#register_open_frame[loading='lazy']", visible: :all)
  expect(page).to have_no_css("#compliance_section_bar")
end

Then('the home pane is drawn inline with the {string} pane as a lazy frame') do |section|
  expect(find_by_id(ComplianceHub.pane_id(:home))).to have_css("#compliance_funds")
  frame = find("turbo-frame##{ComplianceHub.frame_id(section.to_sym)}", visible: :all)
  expect(frame[:loading]).to eq("lazy")
  expect(frame[:src]).to eq(compliance_duties_path)
end

# ── E201 / E202 / X95: step popups and minimise ─────────────────────────────────────────────────
# E201 — the circle carries the shared journey-step-info action and its popup URL, as on other journeys
Then('the {string} step circle opens its popup') do |key|
  circle = find_by_id("gs_step_#{key}")
  expect(circle["data-action"]).to include("journey-step-info#open")
  expect(circle["data-journey-step-info-url-param"]).to eq(compliance_getting_started_step_path(key:))
end

# What journey_step_info_controller.js fetches when the circle is clicked
When('I open the Getting started popup for {string}') do |key|
  visit compliance_getting_started_step_path(key:)
end

Then('the step popup is titled {string}') do |title|
  expect(find_by_id("journeyStepInfoModalLabel", visible: :all)).to have_text(title)
end

Then('the step popup lists {string}') do |text|
  expect(find_by_id("getting_started_step_details", visible: :all)).to have_text(text)
end

Then('the step popup has the button {string}') do |label|
  expect(find_by_id("getting_started_step_action", visible: :all)).to have_text(label)
end

Then('the Getting started steps are expanded') do
  expect(find_by_id("getting_started_body", visible: :all)[:class].split).to include("show")
end

# E202 — what collapse-preference sends on Bootstrap's hidden.bs.collapse
When('I minimise Getting started') do
  page.driver.submit :patch, compliance_getting_started_collapse_path, { collapsed: "true" }
end

Then('the Getting started steps are folded under the header') do
  expect(find_by_id("getting_started_body", visible: :all)[:class].split).not_to include("show")
  expect(find_by_id("getting_started_toggle")["aria-expanded"]).to eq("false")
end

# X95
When('I request the Getting started step popup {string}') do |key|
  visit compliance_getting_started_step_path(key:)
end

Then('the compliance request is not found') do
  expect(page.status_code).to eq(404)
end
