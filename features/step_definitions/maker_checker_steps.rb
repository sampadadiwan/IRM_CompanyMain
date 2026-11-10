# frozen_string_literal: true

# Steps for capital call & distribution maker–checker (OWASP review 2026-11 M13,
# openspec/changes/capital-call-distribution-maker-checker — business-rules.md has every H/E/X row):
#   features/funds/maker_checker/maker_checker_setting.feature        F1 (§1)
#   features/funds/maker_checker/preparers.feature                    F2 (§2)
#   features/funds/maker_checker/capital_call_approval.feature        F3 (§3)
#   features/funds/maker_checker/capital_distribution_approval.feature F4 (§4)
#   features/security/maker_checker_approval.feature                  F5 (§5)
#   features/funds/maker_checker/approval_requests.feature            F6 (§6, §8)
#   features/funds/maker_checker/approval_withdrawal.feature          F7 (§7)
#
# The people are the cast in business-rules.md "Shared setup": Nilgiri Capital (Ravi, Meera, Anil, Priya, Tara,
# Deepa, Vikram), Solo Ventures (Sam), Kaveri Partners (Kiran), the LP Arun and CapHive support Sunil. Each person,
# firm and fund is created on first mention.
#
# Actions go through a bare Rails integration session per person (a "browser") or a bearer-token API client, so the
# controllers, policies, callbacks and Current.user run exactly as in production, with no JavaScript. Setup steps
# that stand for "this person did it earlier" run the same operations under Current.user + the audit user (mc_as),
# which is what a request does. Jobs run inline under Cucumber.

module MakerCheckerWorld
  # firm → its fund and the commitments of its investors (INR rupees)
  MC_FIRMS = {
    "Nilgiri Capital" => { type: "Investment Fund", fund: "Nilgiri Growth Fund I",
                           commitments: [["Arun Pillai", 200_000_000], ["Coromandel Trust", 180_000_000], ["Deccan Family Office", 120_000_000]] },
    "Solo Ventures" => { type: "Investment Fund", fund: "Solo Fund I", commitments: [["Leela Rao", 50_000_000]] },
    "Kaveri Partners" => { type: "Investment Fund", fund: "Kaveri Fund I", commitments: [["Mysore Holdings", 10_000_000]] },
    "CapHive" => { type: "Company" }
  }.freeze

  # first name → last name, firm, roles, fund access (:update / :read / nil), inactive, two-factor
  MC_CAST = {
    "Ravi" => { last: "Iyer", firm: "Nilgiri Capital", roles: %i[company_admin approver] },
    "Meera" => { last: "Shah", firm: "Nilgiri Capital", roles: %i[employee approver], access: :update },
    "Anil" => { last: "Rao", firm: "Nilgiri Capital", roles: %i[employee], access: :update },
    "Priya" => { last: "Nair", firm: "Nilgiri Capital", roles: %i[employee approver], access: :update },
    "Tara" => { last: "Bose", firm: "Nilgiri Capital", roles: %i[employee approver] },
    "Deepa" => { last: "Kumar", firm: "Nilgiri Capital", roles: %i[employee approver], access: :update, inactive: true },
    "Vikram" => { last: "Sen", firm: "Nilgiri Capital", roles: %i[employee], access: :read },
    "Sam" => { last: "Mehta", firm: "Solo Ventures", roles: %i[company_admin approver] },
    "Kiran" => { last: "Das", firm: "Kaveri Partners", roles: %i[company_admin approver] },
    # CapHive support must use two-factor (M8), so Sunil has an authenticator like real staff
    "Sunil" => { last: "Menon", firm: "CapHive", roles: %i[support], tfa: true },
    # The LP of Nilgiri Growth Fund I (the ₹20 Cr commitment)
    "Arun" => { last: "Pillai", investor_of: "Nilgiri Capital", roles: %i[investor] }
  }.freeze

  CALL_DATE = Date.new(2026, 11, 16)
  DUE_DATE = Date.new(2026, 12, 15)

  # ── firms, funds, people ──────────────────────────────────────────────────

  def mc_firm(name)
    @mc_firms ||= {}
    @mc_firms[name] ||= Entity.find_by(name:) || begin
      spec = MakerCheckerWorld::MC_FIRMS.fetch(name, { type: "Investment Fund" })
      FactoryBot.create(:entity, name:, entity_type: spec[:type], enable_funds: true, currency: "INR")
    end
  end

  # The firm's fund, with its investors' commitments (Arun ₹20 Cr, ₹18 Cr, ₹12 Cr for Nilgiri)
  def mc_fund(firm_name)
    @mc_funds ||= {}
    @mc_funds[firm_name] ||= begin
      spec = MakerCheckerWorld::MC_FIRMS.fetch(firm_name)
      firm = mc_firm(firm_name)
      fund = Fund.find_by(entity: firm, name: spec[:fund]) ||
             FactoryBot.create(:fund, entity: firm, name: spec[:fund], currency: "INR", unit_types: nil)
      spec[:commitments].each { |investor_name, rupees| mc_add_commitment(fund, investor_name, rupees) } if fund.capital_commitments.none?
      fund
    end
  end

  def mc_add_commitment(fund, investor_name, rupees)
    investor_entity = Entity.find_by(name: investor_name) || FactoryBot.create(:entity, name: investor_name, entity_type: "Investor")
    investor = Investor.find_by(entity_id: fund.entity_id, investor_entity_id: investor_entity.id) ||
               FactoryBot.create(:investor, entity: fund.entity, investor_entity:, investor_name:)
    commitment = FactoryBot.build(:capital_commitment, fund:, entity: fund.entity, investor:, unit_type: nil,
                                                       folio_currency: "INR", orig_folio_committed_amount_cents: rupees * 100)
    result = CapitalCommitmentCreate.call(capital_commitment: commitment)
    expect(result).to be_success, "commitment for #{investor_name}: #{commitment.errors.full_messages}"
    commitment
  end

  def mc_email(first)
    spec = MakerCheckerWorld::MC_CAST.fetch(first)
    domain = (spec[:firm] || spec[:investor_of]).parameterize
    "#{first.downcase}.#{spec[:last].downcase}@#{domain}.mc.test"
  end

  # The cast member, created on first use
  def mc_user(name)
    @mc_users ||= {}
    @mc_users[name] ||= User.with_deleted.find_by(email: mc_email(name)) || mc_create_user(name)
  end

  def mc_create_user(name)
    spec = MakerCheckerWorld::MC_CAST.fetch(name)
    entity = if spec[:investor_of]
               mc_fund(spec[:investor_of])
               Entity.find_by!(name: MakerCheckerWorld::MC_FIRMS.fetch(spec[:investor_of])[:commitments].first.first)
             else
               mc_firm(spec[:firm])
             end
    user = FactoryBot.create(:user, entity:, first_name: name, last_name: spec[:last], email: mc_email(name))
    spec[:roles].each { |role| user.add_role(role) }
    if spec[:access]
      permissions = spec[:access] == :update ? %i[create read update destroy] : %i[read]
      AccessRight.create!(entity: user.entity, owner: mc_fund(spec[:firm]), user_id: user.id, notify: false, permissions:)
    end
    user.update!(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "authenticator") if spec[:tfa]
    user.update_columns(active: false) if spec[:inactive]
    user.reload
  end

  def mc_set_setting(firm_name, on)
    mc_firm(firm_name).entity_setting.update!(approval_maker_checker: on)
  end

  # What a request does for the person: Current.user (the change watcher's actor) and the audit user, with a fresh
  # per-request memo
  def mc_as(name, &)
    user = name && mc_user(name)
    ApprovalMakerCache.reset
    result = Current.set(user:) { user ? Audited.audit_class.as_user(user, &) : yield }
    ApprovalMakerCache.reset
    result
  end

  # ── records ───────────────────────────────────────────────────────────────

  def mc_call(name)
    CapitalCall.find_by!(name:)
  end

  def mc_distribution(title)
    CapitalDistribution.find_by!(title:)
  end

  # "₹1.25 Cr" / "₹10,00,000" / "₹0.72 Cr" → rupees
  def mc_inr(text)
    clean = text.delete("₹, ").strip
    clean.end_with?("Cr") ? (clean.delete_suffix("Cr").to_d * 10_000_000) : clean.to_d
  end

  def mc_remittance(call_name, amount)
    cents = (mc_inr(amount) * 100).to_i
    remittance = mc_call(call_name).capital_remittances.reload.find { |r| r.call_amount_cents.to_i == cents }
    expect(remittance).to be_present, "no #{amount} remittance in #{call_name}: #{mc_call(call_name).capital_remittances.map(&:call_amount_cents)}"
    remittance
  end

  def mc_payment(title, amount)
    cents = (mc_inr(amount) * 100).to_i
    payment = mc_distribution(title).capital_distribution_payments.reload.find { |p| p.income_cents.to_i == cents }
    expect(payment).to be_present, "no #{amount} payment in #{title}: #{mc_distribution(title).capital_distribution_payments.map(&:income_cents)}"
    payment
  end

  def mc_create_call(name, firm_name, call_basis: "Percentage of Commitment")
    fund = mc_fund(firm_name)
    call = CapitalCall.new(entity: fund.entity, fund:, name:, percentage_called: call_basis == "Upload" ? 0 : 10,
                           call_basis:, fund_closes: ["All"], call_date: MakerCheckerWorld::CALL_DATE,
                           # 10% of every First Close commitment (CapitalRemittanceCallBasis reads the close's percentage)
                           close_percentages: call_basis == "Upload" ? nil : { "First Close" => "10" },
                           due_date: MakerCheckerWorld::DUE_DATE)
    result = CapitalCallCreate.call(capital_call: call)
    expect(result).to be_success, "call #{name}: #{call.errors.full_messages}"
    call.reload
  end

  def mc_create_distribution(title, firm_name, income: 30_000_000)
    fund = mc_fund(firm_name)
    dist = CapitalDistribution.new(entity: fund.entity, fund:, title:, income_cents: income * 100,
                                   cost_of_investment_cents: 0, reinvestment_cents: 0,
                                   distribution_date: MakerCheckerWorld::DUE_DATE, generate_payments: true)
    result = CapitalDistributionCreate.call(capital_distribution: dist)
    expect(result).to be_success, "distribution #{title}: #{dist.errors.full_messages}"
    dist.reload
  end

  def mc_firm_of(name)
    MakerCheckerWorld::MC_CAST.fetch(name)[:firm]
  end

  # ── browsers and the API ──────────────────────────────────────────────────

  def mc_browser(name, fresh: false)
    @mc_browsers ||= {}
    @mc_browsers.delete(name) if fresh
    @mc_browsers[name] ||= ActionDispatch::Integration::Session.new(Rails.application)
  end

  def mc_signed_in?(name)
    (@mc_signed_in ||= {})[name]
  end

  def mc_sign_in(name)
    return if mc_signed_in?(name)

    browser = mc_browser(name, fresh: true)
    browser.post("/users/sign_in", params: { user: { email: mc_user(name).email, password: "password" } })
    # CapHive support always answers the code step (M8)
    if browser.response.location.to_s.include?("/two_factor/new")
      user = mc_user(name).reload
      travel(31.seconds) if user.consumed_timestep.to_i >= Time.now.to_i / 30
      browser.post("/two_factor", params: { otp_code: user.current_otp })
    end
    expect(browser.response.location.to_s).not_to include("/users/sign_in")
    @mc_signed_in[name] = true
  end

  # A request as the person; the answer (after following redirects for a page) is kept for the Then steps
  def mc_request(name, verb, path, params: {})
    mc_sign_in(name)
    browser = mc_browser(name)
    browser.public_send(verb, path, params:)
    @mc_last_name = name
    @mc_last_response = browser.response
    @mc_last_flash = browser.request.flash.to_h
    3.times do
      break unless browser.response.redirect?

      browser.follow_redirect!
    end
    @mc_last_page = browser.response.body
    browser.response
  end

  def mc_page
    Capybara.string(@mc_last_page || raise("no page opened yet"))
  end

  # Visible text of the last page, whitespace squeezed (so line breaks in the ERB don't matter)
  def mc_page_text
    mc_page.text.squish
  end

  # CapHive support signs in afresh (their own session, two-factor) and uses Login as on the client user
  def mc_act_as(support, name)
    (@mc_signed_in ||= {}).delete(support)
    mc_request(support, :post, "/users/#{mc_user(name).id}/login_as")
    expect(@mc_last_flash.values.join(" ")).to include("Signed in as #{mc_user(name).full_name}")
  end

  # Bearer-token API, the same client the API features use (api_json_steps.rb)
  def mc_api(name, verb, path, body = nil)
    @mc_api_clients ||= {}
    client = @mc_api_clients[name] ||= begin
      user = mc_user(name)
      token = Devise::Api::Token.create!(resource_owner: user, access_token: Devise::Api::Token.generate_uniq_access_token(user),
                                         refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user), expires_in: 1.day.to_i)
      ApiJsonClient.new.tap { |c| c.access_token = token.access_token }
    end
    @mc_api_response = client.call(verb, path, body&.to_json)
  end

  # ── mail and bell ─────────────────────────────────────────────────────────

  def mc_mails
    ActionMailer::Base.deliveries.select { |mail| mail.subject.to_s.match?(/needs your approval|was withdrawn|Maker–checker for calls/) }
  end

  def mc_mail_text(mail)
    part = mail.html_part || mail.text_part || mail
    Capybara.string(part.decoded).text.squish
  end

  def mc_bell_messages(name)
    Noticed::Notification.where(recipient: mc_user(name)).includes(:event).map(&:event)
                         .grep(MakerCheckerNotifier).map { |event| event.params.to_h.with_indifferent_access[:message] }
  end

  def mc_names(list)
    list.split(/,| and /).map(&:strip).compact_blank
  end
end
World(MakerCheckerWorld)

# Every scenario starts with an empty per-request memo (the Cucumber thread is reused) and ends back in real time
Before("@maker_checker") do
  ApprovalMakerCache.reset
end

After("@maker_checker") do
  travel_back
end

# ── Setup ────────────────────────────────────────────────────────────────────

Given("the firm {string} has maker-checker {word}") do |firm, state|
  mc_fund(firm) if MakerCheckerWorld::MC_FIRMS.dig(firm, :fund)
  mc_set_setting(firm, state == "on")
end

Given("{string} created the call {string}") do |name, call|
  mc_as(name) { mc_create_call(call, mc_firm_of(name)) }
end

Given("{string} created the upload-basis call {string}") do |name, call|
  mc_as(name) { mc_create_call(call, mc_firm_of(name), call_basis: "Upload") }
end

Given("{string} created the distribution {string}") do |name, title|
  mc_as(name) { mc_create_distribution(title, mc_firm_of(name)) }
end

# E12 — a call created before this change shipped: its creator is only in the audit trail, the log has no row
Given("{string} created the call {string} before maker-checker existed") do |name, call|
  mc_as(name) { mc_create_call(call, mc_firm_of(name)) }
  ApprovalMaker.where(approvable: mc_call(call)).delete_all
end

# Setup only: the approval as the approve button records it (the policy is tested by the When steps)
Given("{string} approved the call {string}") do |name, call|
  mc_as(name) do
    result = CapitalCallApproval.call(capital_call: mc_call(call), user: mc_user(name))
    expect(result).to be_success, result.errors.to_s
  end
  expect(mc_call(call).approved).to be(true)
end

Given("{string} approved the distribution {string}") do |name, title|
  mc_as(name) do
    dist = mc_distribution(title)
    dist.update!(approved: true, approved_by_user: mc_user(name))
  end
end

Given("{string} has fund access to {string}") do |name, firm|
  AccessRight.create!(entity: mc_firm(firm), owner: mc_fund(firm), user_id: mc_user(name).id, notify: false,
                      permissions: %i[create read update destroy])
end

Given("{string} and {string} lose the Approver role") do |first, second|
  [first, second].each { |name| mc_user(name).remove_role(:approver) }
end

Given("CapHive support {string} supports {string}") do |name, firm|
  entity = mc_firm(firm)
  entity.permissions.set(:enable_support)
  entity.save!(validate: false)
  FactoryBot.create(:support_client_mapping, user: mc_user(name), entity:, enabled: true, enable_user_login: true,
                                             end_date: Date.new(2027, 12, 31))
end

Given("the time is {string}") do |time|
  travel_to Time.zone.parse(time)
  # A jump in time outlives the session cookie (expire_after): everyone signs in again on their next request
  @mc_signed_in = {}
end

Given("{string} and {string} can approve {string}") do |first, second, _record|
  [first, second].each { |name| mc_user(name) }
end

Given("{string}, {string} and {string} can approve {string}") do |first, second, third, _record|
  [first, second, third].each { |name| mc_user(name) }
end

# Everyone in "Shared setup", so the recipient lists can be checked against people who must NOT be told
Given("the whole Nilgiri cast exists") do
  %w[Ravi Meera Anil Priya Tara Deepa Vikram Arun Kiran].each { |name| mc_user(name) }
end

# E22 / E23 — a generated call notice still waiting for approval on one remittance
Given("the call {string} has an unapproved generated notice") do |call_name|
  remittance = mc_call(call_name).capital_remittances.first
  folder = FactoryBot.create(:folder, entity: remittance.entity)
  FactoryBot.create(:document, entity: remittance.entity, user: mc_user("Meera"), folder:, owner: remittance,
                               owner_tag: "Generated", approved: false)
end

# E30 — an imported distribution: history, never approved in CapHive (manual_generation)
Given("the distribution {string} was imported") do |title|
  mc_distribution(title).update_columns(manual_generation: true)
end

# E51 — the call notices already went to investors (a one-way flag on each remittance)
Given("the notices of {string} were sent") do |call|
  mc_call(call).capital_remittances.update_all(notification_sent: true)
end

# X16 — a data fix left the call failing a validation that has nothing to do with the edit (a blank due date)
Given("the call {string} fails an unrelated validation") do |call|
  mc_call(call).update_columns(due_date: nil)
end

# ── Imports (H7, H8, E17) ────────────────────────────────────────────────────

# The importer's sheet, run by the import job as that person (ApplicationJob restores Current.user = the uploader)
def mc_import(name, import_type, headers, rows)
  path = Rails.root.join("tmp", "mc_#{import_type.underscore}_#{SecureRandom.hex(4)}.xlsx")
  package = Axlsx::Package.new
  package.workbook.add_worksheet(name: "Sheet1") do |sheet|
    sheet.add_row(headers)
    rows.each { |row| sheet.add_row(row) }
  end
  package.serialize(path.to_s)
  user = mc_user(name)
  firm = user.entity
  upload = ImportUpload.create!(entity: firm, owner: mc_fund(firm.name), import_type:, name: "Import #{import_type}",
                                user_id: user.id, import_file: File.open(path))
  mc_as(name) { ImportUploadJob.perform_now(upload.id) }
  upload.reload
  expect(upload.failed_row_count).to eq(0), "import errors: #{begin
    upload.import_results
  rescue StandardError
    upload.inspect
  end}"
  File.delete(path)
end

Given("{string} imported the call {string}") do |name, call|
  fund = mc_fund(mc_firm_of(name))
  mc_import(name, "CapitalCall",
            ["Fund *", "Name *", "Percentage Called *", "Call Date *", "Due Date *", "Generate Remittances", "Remittances Verified",
             "Fund Closes", "Call Basis", "Unit Price/Premium", "Send Payment Notification", "Send Call Notice"],
            [[fund.name, call, 10, MakerCheckerWorld::CALL_DATE, MakerCheckerWorld::DUE_DATE, "Yes", "No", "All", "Percentage of Commitment", nil, "Yes", "Yes"]])
end

Given("{string} imported {int} remittances into {string}") do |name, count, call|
  fund = mc_fund(mc_firm_of(name))
  rows = fund.capital_commitments.order(:id).first(count).map do |commitment|
    [fund.name, call, commitment.folio_id, 1_000_000, 0, 0, nil, nil, nil, 0, nil, "No"]
  end
  mc_import(name, "CapitalRemittance",
            ["Fund *", "Capital Call *", "Folio No*", "Call Amount (Inclusive of Capital Fees, Folio Currency)*",
             "Capital Fees (Folio Currency)", "Other Fees (Folio Currency)", "Call Amount (Inclusive of Capital Fees, Fund Currency)*",
             "Capital Fees (Fund Currency)", "Other Fees (Fund Currency)", "Investment Amount (Fund Currency)", "Remittance Date", "Verified"],
            rows)
end

# ── Fees (H9, H10, E46, E47) ─────────────────────────────────────────────────

# A "Management Fee" call fee line read from each folio's account entries; ₹1,00,000 per folio before the call date
Given("the call {string} charges a management fee from account entries") do |call_name|
  call = mc_call(call_name)
  call.capital_commitments.distinct.each do |commitment|
    FactoryBot.create(:account_entry, entity: call.entity, fund: call.fund, capital_commitment: commitment,
                                      investor: commitment.investor, folio_id: commitment.folio_id, name: "Management Fee",
                                      entry_type: "Expense", reporting_date: Date.new(2026, 10, 1), amount: 100_000,
                                      cumulative: false)
  end
  CallFee.create!(entity: call.entity, fund: call.fund, capital_call: call, name: "Management Fee",
                  start_date: Date.new(2026, 4, 1), end_date: Date.new(2026, 10, 31), fee_type: "Other Fees")
  # The fees as they were when the call was prepared (nobody is recorded: no acting user)
  mc_as(nil) { call.capital_remittances.each { |remittance| CapitalRemittanceUpdate.call(capital_remittance: remittance.reload) } }
end

Given("the management fee account entries of {string} grow to ₹1,20,000 per folio") do |call_name|
  AccountEntry.where(fund_id: mc_call(call_name).fund_id, name: "Management Fee").update_all(amount_cents: 12_000_000)
end

When("{string} clicks Recompute Fees on {string}") do |name, call|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}/recompute_fees")
end

When("{string} changes the end date of the fee line of {string}") do |name, call_name|
  call = mc_call(call_name)
  fee = call.call_fees.first
  mc_request(name, :patch, "/capital_calls/#{call.id}",
             params: { capital_call: { call_fees_attributes: { "0" => { id: fee.id, name: fee.name, start_date: fee.start_date,
                                                                        end_date: Date.new(2026, 11, 15), fee_type: fee.fee_type } } } })
end

# ── Actions ──────────────────────────────────────────────────────────────────

When("{string} opens the call {string}") do |name, call|
  mc_request(name, :get, "/capital_calls/#{mc_call(call).id}")
end

When("{string} opens the distribution {string}") do |name, title|
  mc_request(name, :get, "/capital_distributions/#{mc_distribution(title).id}")
end

When("{string} creates the call {string} on the form") do |name, call|
  fund = mc_fund(mc_firm_of(name))
  mc_request(name, :post, "/capital_calls",
             params: { capital_call: { entity_id: fund.entity_id, fund_id: fund.id, name: call, percentage_called: 10,
                                       call_date: MakerCheckerWorld::CALL_DATE, due_date: MakerCheckerWorld::DUE_DATE,
                                       call_basis: "Percentage of Commitment", fund_closes: ["All"], close_percentages: { "First Close" => "10" } } })
end

When("{string} creates the call {string} through the API") do |name, call|
  fund = mc_fund(mc_firm_of(name))
  mc_api(name, :post, "/capital_calls.json",
         { capital_call: { entity_id: fund.entity_id, fund_id: fund.id, name: call, percentage_called: 10,
                           call_date: MakerCheckerWorld::CALL_DATE.iso8601, due_date: MakerCheckerWorld::DUE_DATE.iso8601,
                           call_basis: "Percentage of Commitment", fund_closes: ["All"], close_percentages: { "First Close" => "10" } } })
  expect(@mc_api_response.status).to eq(201), @mc_api_response.body
end

When("{string} creates the distribution {string} on the form") do |name, title|
  fund = mc_fund(mc_firm_of(name))
  mc_request(name, :post, "/capital_distributions",
             params: { capital_distribution: { entity_id: fund.entity_id, fund_id: fund.id, title:, income: 30_000_000,
                                               cost_of_investment: 0, reinvestment: 0, generate_payments: true,
                                               distribution_date: MakerCheckerWorld::DUE_DATE } })
end

# CapHive support signs in, uses Login as on the client user, then acts
When("CapHive support {string} acting as {string} creates the call {string}") do |support, name, call|
  mc_act_as(support, name)
  fund = mc_fund(mc_firm_of(name))
  mc_request(support, :post, "/capital_calls",
             params: { capital_call: { entity_id: fund.entity_id, fund_id: fund.id, name: call, percentage_called: 10,
                                       call_date: MakerCheckerWorld::CALL_DATE, due_date: MakerCheckerWorld::DUE_DATE,
                                       call_basis: "Percentage of Commitment", fund_closes: ["All"], close_percentages: { "First Close" => "10" } } })
end

When("CapHive support {string} acting as {string} approves the call {string}") do |support, name, call|
  mc_act_as(support, name)
  mc_request(support, :post, "/capital_calls/#{mc_call(call).id}/approve")
end

When("{string} approves the call {string}") do |name, call|
  mc_request(name, :post, "/capital_calls/#{mc_call(call).id}/approve")
end

When("{string} unapproves the call {string}") do |name, call|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}/unapprove")
end

When("{string} approves the distribution {string}") do |name, title|
  mc_request(name, :post, "/capital_distributions/#{mc_distribution(title).id}/approve")
end

When("{string} marks the payments of {string} completed") do |name, title|
  mc_request(name, :patch, "/capital_distributions/#{mc_distribution(title).id}/payments_completed")
end

When("{string} approves the call {string} through the API") do |name, call|
  mc_api(name, :post, "/capital_calls/#{mc_call(call).id}/approve.json")
end

When("{string} approves the distribution {string} through the API") do |name, title|
  mc_api(name, :post, "/capital_distributions/#{mc_distribution(title).id}/approve.json")
end

When("{string} bulk-approves the calls of {string} through the API") do |name, firm|
  mc_api(name, :post, "/capital_calls/bulk_actions.json?fund_id=#{mc_fund(firm).id}&bulk_action=approve")
end

When("{string} bulk-approves the distributions of {string} through the API") do |name, firm|
  mc_api(name, :post, "/capital_distributions/bulk_actions.json?fund_id=#{mc_fund(firm).id}&bulk_action=approve")
end

When("{string} sends approved and approved_by_user_id in an edit of {string}") do |name, call_name|
  call = mc_call(call_name)
  mc_request(name, :patch, "/capital_calls/#{call.id}",
             params: { capital_call: { name: call.name, approved: "1", approved_by_user_id: mc_user(name).id } })
end

When("{string} changes the percentage of {string} to {int}%") do |name, call, percentage|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}", params: { capital_call: { percentage_called: percentage } })
end

When("{string} edits the name and notes of {string}") do |name, call|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}",
             params: { capital_call: { name: "#{call} (Nov)", notes: "Revised cover note" } })
  mc_call("#{call} (Nov)").update_columns(name: call)
end

When("{string} edits the notes of {string}") do |name, call|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}", params: { capital_call: { notes: "Revised cover note" } })
end

When("{string} changes the custom fields and the Send Call Notice switch of {string}") do |name, call|
  mc_request(name, :patch, "/capital_calls/#{mc_call(call).id}",
             params: { capital_call: { send_call_notice_flag: "0", properties: { purpose: "Bridge to exit" } } })
end

When("{string} changes the {string} remittance of {string} to {string}") do |name, from, call, to|
  remittance = mc_remittance(call, from)
  mc_request(name, :patch, "/capital_remittances/#{remittance.id}", params: { capital_remittance: { call_amount: mc_inr(to).to_s("F") } })
end

When("{string} saves the {string} remittance of {string} without changes") do |name, amount, call|
  remittance = mc_remittance(call, amount)
  mc_request(name, :patch, "/capital_remittances/#{remittance.id}", params: { capital_remittance: { call_amount: mc_inr(amount).to_s("F") } })
end

When("{string} deletes the {string} remittance of {string}") do |name, amount, call|
  mc_request(name, :delete, "/capital_remittances/#{mc_remittance(call, amount).id}")
end

When("{string} deletes the call {string}") do |name, call|
  mc_request(name, :delete, "/capital_calls/#{mc_call(call).id}")
end

# E10 / E45 — a job with nobody behind it (cron, console): no Current.user
When("a job with no acting user changes the {string} remittance of {string} to {string}") do |from, call, to|
  remittance = mc_remittance(call, from)
  # The warning E45 expects goes to the log; capture it alongside the normal log
  captured = StringIO.new
  original_logger = Rails.logger
  Rails.logger = ActiveSupport::BroadcastLogger.new(original_logger, ActiveSupport::Logger.new(captured))
  mc_as(nil) do
    remittance.call_amount_cents = mc_inr(to) * 100
    expect(CapitalRemittanceUpdate.call(capital_remittance: remittance)).to be_success
  end
ensure
  Rails.logger = original_logger if original_logger
  @mc_logged = captured&.string
end

When("{string} records a payment of {string} on the {string} remittance of {string}") do |name, paid, amount, call|
  remittance = mc_remittance(call, amount)
  mc_request(name, :post, "/capital_remittance_payments",
             params: { capital_remittance_payment: { capital_remittance_id: remittance.id, fund_id: remittance.fund_id,
                                                     entity_id: remittance.entity_id, folio_amount: mc_inr(paid).to_s("F"),
                                                     payment_date: MakerCheckerWorld::CALL_DATE } })
end

When("{string} verifies the {string} remittance of {string}") do |name, amount, call|
  mc_request(name, :patch, "/capital_remittances/#{mc_remittance(call, amount).id}/verify")
end

When("{string} changes the income of the {string} payment of {string} to {string}") do |name, from, title, to|
  payment = mc_payment(title, from)
  mc_request(name, :patch, "/capital_distribution_payments/#{payment.id}",
             params: { capital_distribution_payment: { income: mc_inr(to).to_s("F") } })
end

When("{string} changes the distribution date of {string}") do |name, title|
  mc_request(name, :patch, "/capital_distributions/#{mc_distribution(title).id}",
             params: { capital_distribution: { distribution_date: Date.new(2026, 12, 20) } })
end

# E43 — a late closer: CapitalCommitmentRemittanceJob adds a remittance to every existing call
When("{string} adds a {string} commitment for {string} to the fund of {string}") do |name, amount, investor, firm|
  mc_as(name) { mc_add_commitment(mc_fund(firm), investor, mc_inr(amount).to_i) }
end

# ── Entity form (F1, F6 §8) ──────────────────────────────────────────────────

When("{string} switches maker-checker {word} on the entity form") do |name, state|
  entity = mc_user(name).entity
  mc_request(name, :patch, "/entities/#{entity.id}",
             params: { entity: { name: entity.name, entity_setting_attributes: { id: entity.entity_setting.id,
                                                                                 approval_maker_checker: state == "on" ? "1" : "0" } } })
end

When("{string} saves the entity form of {string} with maker-checker {word}") do |name, firm, state|
  entity = mc_firm(firm)
  mc_request(name, :patch, "/entities/#{entity.id}",
             params: { entity: { entity_setting_attributes: { id: entity.entity_setting.id, approval_maker_checker: state == "on" ? "1" : "0" } } })
end

When("{string} saves the entity form with only a new name") do |name|
  entity = mc_user(name).entity
  mc_request(name, :patch, "/entities/#{entity.id}", params: { entity: { name: "#{entity.name} " } })
end

When("{string} opens the entity form") do |name|
  mc_request(name, :get, "/entities/#{mc_user(name).entity_id}/edit")
end

# H1 / U.1 — the Approvals block: the switch, its ⓘ (who counts as a preparer) and the help line (switching off)
Then("the entity form has the maker-checker switch with its explanation") do
  block = mc_page.find("[data-maker-checker='setting']")
  expect(block).to have_field("entity[entity_setting_attributes][approval_maker_checker]", type: "checkbox", visible: :all)
  expect(block.text.squish).to include("Require a second person to approve capital calls and distributions")
  expect(block.text.squish).to include("Switching this off alerts your other company admins and approvers.")
  tip = block.find("[data-bs-toggle='tooltip']")
  expect(tip["title"]).to include("Whoever created, imported or changed a call's or distribution's figures cannot approve it.")
end

When("CapHive support creates the firm {string}") do |firm|
  FactoryBot.create(:entity, name: firm, entity_type: "Investment Fund", enable_funds: true, currency: "INR")
end

# ── Request approval (F6) ────────────────────────────────────────────────────

When("{string} requests approval of the call {string}") do |name, call|
  mc_request(name, :post, "/capital_calls/#{mc_call(call).id}/request_approval")
end

When("{string} requests approval of the distribution {string}") do |name, title|
  mc_request(name, :post, "/capital_distributions/#{mc_distribution(title).id}/request_approval")
end

When("{string} follows the link in the maker-checker email") do |name|
  mail = mc_mails.rfind { |m| m.to.include?(mc_user(name).email) }
  expect(mail).to be_present
  href = Capybara.string((mail.html_part || mail).decoded).find(:link, text: /Open (call|distribution)/)[:href]
  mc_request(name, :get, URI.parse(href).path)
end

# ── Journey (E24, E25) ───────────────────────────────────────────────────────

When("the Approve call journey check runs for {string}") do |call|
  @mc_check = WorkflowChecks::CapitalCall::ApproveCall.new.call(mc_call(call).reload)
end

Then("the journey check says {string}") do |text|
  expect(@mc_check.message).to eq(text)
end

# ── Open-ended settlements (E27, E31, E50) ───────────────────────────────────

Given("the fund of {string} settles a dealing date") do |firm|
  fund = mc_fund(firm)
  date = Date.new(2026, 11, 30)
  @mc_dealing_date = DealingDate.create!(entity_id: fund.entity_id, fund:, date:, cutoff_at: date - 5.days,
                                         payment_timing: "before", status: "confirmed", confirmed_at: Time.current)
end

When("{string} creates the subscription settlement") do |name|
  @mc_settlement = mc_as(name) { DealingSettlement.subscription_call(@mc_dealing_date, mc_user(name)) }
end

When("{string} creates the redemption settlement") do |name|
  @mc_settlement = mc_as(name) { DealingSettlement.redemption_distribution(@mc_dealing_date, [], mc_user(name)) }
end

When("{string} adds and then changes a subscription payment on the settlement") do |name|
  call = @mc_settlement.reload
  commitment = call.fund.capital_commitments.first
  mc_as(name) do
    remittance = CapitalRemittance.new(entity_id: call.entity_id, fund_id: call.fund_id, capital_call: call, capital_commitment: commitment,
                                       investor_id: commitment.investor_id, folio_id: commitment.folio_id,
                                       folio_call_amount_cents: 100_000_000, call_amount_cents: 100_000_000,
                                       remittance_date: call.call_date, verified: false)
    expect(CapitalRemittanceCreate.call(capital_remittance: remittance)).to be_success
  end
  mc_as(name) do
    remittance = call.capital_remittances.first
    remittance.call_amount_cents = 120_000_000
    remittance.folio_call_amount_cents = 120_000_000
    expect(CapitalRemittanceUpdate.call(capital_remittance: remittance)).to be_success
  end
end

Then("the settlement is approved with no preparer recorded") do
  settlement = @mc_settlement.reload
  expect(settlement.approved).to be(true)
  expect(ApprovalMaker.where(approvable: settlement)).to be_none
end

# ── Assertions: preparers ────────────────────────────────────────────────────

Then("the preparers of the call {string} are {string}") do |call, names|
  record = mc_call(call)
  expect(record.preparers.map(&:full_name)).to eq(mc_names(names))
end

Then("the preparers of the distribution {string} are {string}") do |title, names|
  record = mc_distribution(title)
  expect(record.preparers.map(&:full_name)).to eq(mc_names(names))
end

Then("{string} is a preparer of the call {string}") do |name, call|
  expect(mc_call(call).preparer_ids).to include(mc_user(name).id)
end

Then("{string} is not a preparer of the call {string}") do |name, call|
  expect(mc_call(call).preparer_ids).not_to include(mc_user(name).id)
end

Then("the call {string} has {int} preparer row(s)") do |call, count|
  expect(ApprovalMaker.where(approvable: mc_call(call)).count).to eq(count)
end

Then("{string} is recorded as {string} on the call {string}") do |name, role, call|
  expect(ApprovalMaker.find_by(approvable: mc_call(call), user: mc_user(name))&.role).to eq(role)
end

# ── Assertions: approval ─────────────────────────────────────────────────────

Then("the call {string} is approved by {string}") do |call, name|
  record = mc_call(call)
  expect(record.approved).to be(true)
  expect(record.approved_by_user_id).to eq(mc_user(name).id)
end

Then("the call {string} is not approved") do |call|
  record = mc_call(call)
  expect(record.approved).to be(false)
  expect(record.approved_by_user_id).to be_nil
end

Then("the distribution {string} is approved by {string}") do |title, name|
  record = mc_distribution(title)
  expect(record.approved).to be(true)
  expect(record.approved_by_user_id).to eq(mc_user(name).id)
end

Then("the distribution {string} is not approved") do |title|
  record = mc_distribution(title)
  expect(record.approved).to be(false)
  expect(record.approved_by_user_id).to be_nil
end

Then("the payments of {string} are completed") do |title|
  expect(mc_distribution(title).capital_distribution_payments.where(completed: false)).to be_none
end

# ── Assertions: pages ────────────────────────────────────────────────────────

Then("{string} sees {string} on the page") do |name, text|
  expect(@mc_last_name).to eq(name)
  expect(mc_page_text).to include(text)
end

Then("{string} sees the flash {string}") do |name, text|
  expect(@mc_last_name).to eq(name)
  flash_text = @mc_last_flash.values.join(" ").squish
  expect(flash_text).to include(text), "flash was #{@mc_last_flash.inspect}"
end

Then("{string} is refused with Access Denied") do |name|
  expect(@mc_last_name).to eq(name)
  expect(@mc_last_response).to be_redirect
  expect(@mc_last_flash.values.join(" ")).to include("Access Denied")
end

Then("the API answers 403 Access Denied") do
  expect(@mc_api_response.status).to eq(403)
  expect(JSON.parse(@mc_api_response.body)).to eq("error" => "Access Denied")
end

Then("the maker-checker API answers {int}") do |status|
  expect(@mc_api_response.status).to eq(status), @mc_api_response.body
end

# H13 / E28 — Approve is shown greyed out, with the reason on a wrapper (tooltips don't fire on disabled items)
Then("the page shows Approve disabled with the reason {string}") do |reason|
  wrapper = mc_page.find("[data-maker-checker='approve-disabled']")
  expect(wrapper["title"] || wrapper["data-bs-title"]).to include(reason)
  expect(wrapper).to have_css("button.dropdown-item.disabled[aria-disabled='true']", text: "Approve")
end

Then("the page shows an enabled Approve") do
  expect(mc_page).to have_css("form[action$='/approve'] button", text: "Approve")
  expect(mc_page).to have_no_css("[data-maker-checker='approve-disabled']")
end

Then("the page shows no Approve") do
  expect(mc_page).to have_no_css("form[action$='/approve'] button")
  expect(mc_page).to have_no_css("[data-maker-checker='approve-disabled']")
end

Then("the page shows Unapprove") do
  expect(mc_page).to have_css("form[action$='/unapprove'] button", text: "Unapprove")
end

Then("the page shows Request approval") do
  expect(mc_page).to have_css("form[action$='/request_approval'] button", text: "Request approval")
end

Then("the page shows no Request approval") do
  expect(mc_page).to have_no_css("form[action$='/request_approval']")
end

# H18 — the popup's three "Immediate Actions" cards, carried on the button (confirm#popup renders them)
Then("the Request approval popup says:") do |table|
  msg = Capybara.string(mc_page.find("form[action$='/request_approval'] button")["data-msg"])
  table.raw.flatten.each { |text| expect(msg.text.squish).to include(text) }
end

Then("the Prepared by row shows {string}") do |names|
  row = mc_page.find("[data-maker-checker='prepared-by']")
  expect(row.text.squish).to include(names)
end

Then("the Prepared by tooltip says {string}") do |text|
  tip = mc_page.find("[data-maker-checker='prepared-by'] [data-bs-toggle='tooltip']")
  expect(tip["title"] || tip["data-bs-title"]).to include(text)
end

Then("the Approved row shows {string}") do |text|
  expect(mc_page.find("[data-maker-checker='approved']").text.squish).to include(text)
end

Then("the Approved row does not mention {string}") do |text|
  expect(mc_page.find("[data-maker-checker='approved']").text.squish).not_to include(text)
end

# ── Assertions: setting ──────────────────────────────────────────────────────

Then("maker-checker is {word} for {string}") do |state, firm|
  expect(mc_firm(firm).entity_setting.reload.approval_maker_checker).to be(state == "on")
end

Then("the entity audit of {string} shows {string} switched maker-checker from {word} to {word}") do |firm, name, from, to|
  setting = mc_firm(firm).entity_setting
  audit = setting.audits.reorder(:id).to_a.rfind { |a| a.audited_changes.key?("approval_maker_checker") }
  expect(audit).to be_present
  expect(audit.user_id).to eq(mc_user(name).id)
  expect(audit.audited_changes["approval_maker_checker"]).to eq([from == "true", to == "true"])
end

Then("the entity audit of {string} has no maker-checker change") do |firm|
  setting = mc_firm(firm).entity_setting
  changes = setting.audits.where(action: "update").map(&:audited_changes)
  expect(changes.count { |c| c.key?("approval_maker_checker") }).to be <= 1 # the Given that switched it on
end

# ── Assertions: mail and bell ────────────────────────────────────────────────

Then("only {string} receive(s) the maker-checker email {string}") do |names, subject|
  mails = mc_mails.select { |mail| mail.subject == subject }
  expect(mails.flat_map(&:to).sort).to eq(mc_names(names).map { |n| mc_email(n) }.sort)
end

Then("{string} has the bell alert {string}") do |name, message|
  expect(mc_bell_messages(name)).to include(message)
end

Then("{string} has no maker-checker bell alert") do |name|
  expect(mc_bell_messages(name)).to be_empty
end

Then("no maker-checker email is sent") do
  expect(mc_mails).to be_empty
  expect(MakerCheckerNotifier.count).to eq(0)
end

Then("the maker-checker email to {string} says {string}") do |name, text|
  mail = mc_mails.rfind { |m| m.to.include?(mc_email(name)) }
  expect(mail).to be_present
  expect(mc_mail_text(mail)).to include(text)
end

Then("the maker-checker email to {string} does not say {string}") do |name, text|
  mail = mc_mails.rfind { |m| m.to.include?(mc_email(name)) }
  expect(mail).to be_present
  expect(mc_mail_text(mail)).not_to include(text)
end

Then("the bulk errors email says {string}") do |text|
  bodies = ActionMailer::Base.deliveries.map { |mail| Capybara.string((mail.html_part || mail).decoded).text.squish }
  expect(bodies.any? { |body| body.include?(text) }).to be(true), "no email mentions #{text.inspect}"
end

Then("{string} receives {int} maker-checker emails") do |name, count|
  expect(mc_mails.count { |mail| mail.to.include?(mc_email(name)) }).to eq(count)
end

# H21 — the withdrawal is an audited save of the call, under the editor's name
Then("the call {string} was withdrawn by {string} in its audit trail") do |call, name|
  audit = mc_call(call).audits.reorder(:id).to_a.rfind { |a| a.audited_changes["approved"] == [true, false] }
  expect(audit).to be_present
  expect(audit.user_id).to eq(mc_user(name).id)
end

Then("the call {string} has a {string} remittance") do |call, amount|
  expect(mc_remittance(call, amount)).to be_present
end

Then("a warning about an unattributed figure change is logged for {string}") do |call|
  expect(@mc_logged.to_s).to include("[MakerChecker] unattributed figure change").and include("CapitalCall=#{mc_call(call).id}")
end
