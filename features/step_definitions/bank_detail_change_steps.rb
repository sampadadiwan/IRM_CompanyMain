# frozen_string_literal: true

# Steps for bank detail change controls (OWASP review 2026-11 M14,
# openspec/changes/archive/2026-11-10-bank-detail-change-controls — business-rules.md has every H/E/X row):
#   features/core/bank_detail_change_reset.feature              §1 Clear on change
#   features/security/bank_detail_change_fields.feature         §2 Protected fields
#   features/core/bank_detail_change_record.feature             §3 Change record and KYC page
#   features/core/bank_detail_change_emails.feature             §4 Change emails
#   features/core/bank_detail_change_second_person.feature      §5 Second person
#   features/security/bank_detail_change_second_person.feature  §5 refusals
#   features/core/bank_detail_name_match.feature                §6 Bank check name rule
#   features/funds/bank_detail_change_payout_flags.feature      §7 Payout flags and journey warnings
#   features/core/bank_detail_payout_fields.feature             §8 Payout custom fields
#   features/security/bank_detail_payout_fields.feature         §8 refusals
#
# The people, firms and KYCs are the cast in business-rules.md "Shared setup": Horizon Capital (checks off: Meera,
# Ravi, Priya, Kabir; KYCs Anil Kumar, Bina Shah, Chetan Rao), Kestrel Capital (checks on: Dev, Asha), Solo
# Advisors (Kiran, Uma), Northwind Partners (Omar) and CapHive support (Sam). Each is created on first mention.
#
# Actions go through a bare Rails integration session per person (a "browser"), a signed magic link, or a
# bearer-token API client, so controllers, policies, the change guard and Current.user run exactly as in
# production, with no JavaScript. Jobs run inline. "Today" is 09/11/2026 (business-rules.md "How to read this").
module BankDetailChangeWorld
  TODAY = Time.zone.local(2026, 11, 9, 10, 0, 0)

  # firm → bank verification (penny drop) on / off
  BDC_FIRMS = {
    "Horizon Capital" => { checks: false },
    "Kestrel Capital" => { checks: true },
    "Solo Advisors" => { checks: false },
    "Northwind Partners" => { checks: false },
    "CapHive" => { type: "Company" }
  }.freeze

  APPROVER = %i[investor_kyc_read investor_kyc_update investor_kyc_approve].freeze

  # first name → last name, firm, company admin?, KYC extended permissions, support (two-factor, M8)
  BDC_CAST = {
    "Meera" => { last: "Shah", firm: "Horizon Capital", kyc: APPROVER },
    "Ravi" => { last: "Iyer", firm: "Horizon Capital", admin: true },
    "Priya" => { last: "Nair", firm: "Horizon Capital", kyc: %i[investor_kyc_update] },
    # Approve, but no KYC read / update and no fund access: cannot see Horizon's KYCs (E30, E39)
    "Kabir" => { last: "Sethi", firm: "Horizon Capital", kyc: %i[investor_kyc_approve] },
    "Dev" => { last: "Menon", firm: "Kestrel Capital", kyc: APPROVER },
    "Asha" => { last: "Pillai", firm: "Kestrel Capital", kyc: APPROVER },
    "Kiran" => { last: "Rao", firm: "Solo Advisors", admin: true },
    "Uma" => { last: "Krishnan", firm: "Solo Advisors", kyc: APPROVER },
    "Omar" => { last: "Sheikh", firm: "Northwind Partners", admin: true },
    "Sam" => { last: "Joseph", firm: "CapHive", support: true }
  }.freeze

  # KYC → firm, kind, bank details, state. verified_by: the approver who verified it on 01/10/2026.
  BDC_KYCS = {
    "Anil Kumar" => { firm: "Horizon Capital", account: "50100012344821", ifsc: "HDFC0001234", bank: "HDFC Bank",
                      branch: "MG Road", verified_by: "Ravi", bank_verified: true,
                      contacts: [["anil.kumar@example.in", nil], ["sunita.kumar@example.in", "Distribution"]] },
    "Bina Shah" => { firm: "Horizon Capital", account: "50100099887766", ifsc: "HDFC0004321", verified_by: "Ravi",
                     bank_verified: true, contacts: [["bina.shah@example.in", nil]] },
    "Chetan Rao" => { firm: "Horizon Capital", account: nil, ifsc: nil, status: "completed",
                      contacts: [["chetan.rao@example.in", nil]] },
    "A Kumar" => { firm: "Kestrel Capital", account: "60200011112222", ifsc: "SBIN0001111", verified_by: "Asha",
                   bank_verified: true, contacts: [["a.kumar@example.in", nil]] },
    "Thimmaiah Chengappa" => { firm: "Kestrel Capital", account: "60200033334444", ifsc: "SBIN0002222",
                               verified_by: "Asha", bank_verified: true },
    "ABC Private Limited" => { firm: "Kestrel Capital", account: "60200055556666", ifsc: "SBIN0003333",
                               verified_by: "Asha", bank_verified: true, kind: "non_individual" },
    "Anil Sharma" => { firm: "Kestrel Capital", account: "60200077778888", ifsc: "SBIN0004444", verified_by: "Asha",
                       bank_verified: true },
    "Leela Menon" => { firm: "Solo Advisors", account: "70300011223344", ifsc: "UTIB0001234", verified_by: "Kiran",
                       bank_verified: true, contacts: [["leela.menon@example.in", nil]] },
    "Farah Ali" => { firm: "Horizon Capital", account: "50100099001122", ifsc: "HDFC0001234", verified_by: "Ravi",
                     bank_verified: true, contacts: [["farah.ali@example.ae", nil]],
                     json: { "swift_code" => "EBILAEADXXX", "iban_code" => "AE070331234567890123456" } },
    "Gulf Ventures LLC" => { firm: "Horizon Capital", account: "50100088776655", ifsc: "HDFC0001234",
                             verified_by: "Ravi", bank_verified: true, kind: "non_individual",
                             json: { "swift_code" => "NBADAEAAXXX" } }
  }.freeze

  # What the scenarios call a field → the KYC column (custom fields go to properties)
  BDC_FIELDS = {
    "account" => "bank_account_number", "IFSC" => "ifsc_code", "bank name" => "bank_name",
    "branch" => "bank_branch", "account type" => "bank_account_type", "full name" => "full_name",
    "address" => "address", "Bank Verified" => "bank_verified", "verified" => "verified",
    "eSign emails" => "esign_emails", "bank verification status" => "bank_verification_status",
    "bank verification response" => "bank_verification_response",
    "PAN verification status" => "pan_verification_status"
  }.freeze

  # ── firms, people, KYCs ───────────────────────────────────────────────────

  def bdc_firm(name)
    @bdc_firms ||= {}
    @bdc_firms[name] ||= Entity.find_by(name:) || begin
      spec = BankDetailChangeWorld::BDC_FIRMS.fetch(name, {})
      firm = FactoryBot.create(:entity, name:, entity_type: spec[:type] || "Investment Fund", enable_kycs: true,
                                        currency: "INR")
      firm.entity_setting.update!(bank_verification: spec[:checks] == true)
      # The two KYC forms (custom fields are added by the §8 steps)
      %w[IndividualKyc NonIndividualKyc].each { |form| FormType.find_or_create_by!(entity: firm, name: form) } unless spec[:type] == "Company"
      firm
    end
  end

  def bdc_email(first)
    spec = BankDetailChangeWorld::BDC_CAST.fetch(first)
    "#{first.downcase}.#{spec[:last].downcase}@#{spec[:firm].parameterize}.bdc.test"
  end

  def bdc_user(first)
    @bdc_users ||= {}
    @bdc_users[first] ||= User.with_deleted.find_by(email: bdc_email(first)) || bdc_create_user(first)
  end

  def bdc_create_user(first)
    spec = BankDetailChangeWorld::BDC_CAST.fetch(first)
    user = FactoryBot.create(:user, entity: bdc_firm(spec[:firm]), first_name: first, last_name: spec[:last],
                                    email: bdc_email(first))
    user.add_role(:company_admin) if spec[:admin]
    user.add_role(:support) if spec[:support]
    Array(spec[:kyc]).each { |perm| user.extended_permissions.set(perm) }
    # CapHive support must use two-factor (M8): an authenticator, answered at sign-in
    user.assign_attributes(two_factor_enabled: true, otp_secret: User.generate_otp_secret, two_factor_mode: "authenticator") if spec[:support]
    user.save!
    user.reload
  end

  def bdc_full_name(first)
    "#{first} #{BankDetailChangeWorld::BDC_CAST.fetch(first)[:last]}"
  end

  # The investor contact (portal user) behind an email
  def bdc_contact(email)
    User.find_by!(email:)
  end

  def bdc_kyc(name)
    @bdc_kycs ||= {}
    (@bdc_kycs[name] ||= InvestorKyc.find_by(full_name: name) || bdc_create_kyc(name)).reload
  end

  def bdc_create_kyc(name)
    spec = BankDetailChangeWorld::BDC_KYCS.fetch(name)
    firm = bdc_firm(spec[:firm])
    investor_entity = Entity.find_by(name:) || FactoryBot.create(:entity, name:, entity_type: "Investor")
    investor = Investor.find_by(entity_id: firm.id, investor_entity_id: investor_entity.id) ||
               FactoryBot.create(:investor, entity: firm, investor_entity:, investor_name: name)
    # Contacts approved on 01/10/2026 (E25 compares their access date with the change)
    Array(spec[:contacts]).each { |email, tag| bdc_add_contact(investor, email, tag:, at: Time.zone.local(2026, 10, 1, 9)) }
    verified = spec[:verified_by].present?
    kind = spec[:kind] || "individual"
    form_type = FormType.find_by(entity: firm, name: kind == "individual" ? "IndividualKyc" : "NonIndividualKyc")
    kyc = FactoryBot.build(:investor_kyc, entity: firm, investor:, kyc_type: kind, full_name: name,
                                          PAN: "AAAP#{name.delete(' ').upcase[0, 5].ljust(5, 'X')}1",
                                          address: "14 Residency Road, Bengaluru 560025", birth_date: Date.new(1980, 5, 1),
                                          bank_name: spec[:bank] || "HDFC Bank", bank_branch: spec[:branch] || "MG Road",
                                          bank_account_type: "Savings Account", bank_account_number: spec[:account],
                                          ifsc_code: spec[:ifsc], bank_verified: spec[:bank_verified] == true,
                                          verified:, completed_by_investor: verified || spec[:status] == "completed",
                                          verified_by_id: verified ? bdc_user(spec[:verified_by]).id : nil,
                                          submission_status: verified ? "verified" : (spec[:status] || "not_sent"),
                                          form_type:, json_fields: spec[:json] || {}, esign_emails: nil)
    kyc.type = kyc.type_from_kyc_type
    # A firm with bank checks on keeps the penny drop's answer for a Bank Verified account
    kyc.bank_verification_response = { "verified" => true, "beneficiary_name_with_bank" => name.upcase, "fuzzy_match_result" => true } if spec[:bank_verified] && BankDetailChangeWorld::BDC_FIRMS.dig(spec[:firm], :checks)
    kyc.save!(validate: false)
    kyc.update_columns(created_at: Time.zone.local(2026, 10, 1, 9), updated_at: Time.zone.local(2026, 10, 1, 9))
    InvestorKyc.find(kyc.id)
  end

  def bdc_add_contact(investor, email, tag: nil, at: Time.current)
    first, last = email.split("@").first.split(".").map(&:capitalize)
    access = FactoryBot.create(:investor_access, entity: investor.entity, investor:, email:, first_name: first,
                                                 last_name: last || "Contact", approved: true, tag_list: tag)
    access.update_columns(created_at: at, updated_at: at)
    # The portal user the access created (random password) signs in like the cast
    if access.user
      access.user.password = "password"
      access.user.save!(validate: false)
    end
    access
  end

  # ── acting as someone ─────────────────────────────────────────────────────

  # What a request does for the person: Current.user and the audit user (setup steps standing for "they did it")
  def bdc_as(first, &)
    user = first && bdc_user(first)
    Current.set(user:) { user ? Audited.audit_class.as_user(user, &) : yield }
  end

  def bdc_browser(key, fresh: false)
    @bdc_browsers ||= {}
    @bdc_browsers.delete(key) if fresh
    @bdc_browsers[key] ||= ActionDispatch::Integration::Session.new(Rails.application)
  end

  # Signs in a cast member (first name) or an investor contact (email) through the sign-in form
  def bdc_sign_in(key)
    @bdc_signed_in ||= {}
    return if @bdc_signed_in[key]

    user = key.include?("@") ? bdc_contact(key) : bdc_user(key)
    browser = bdc_browser(key, fresh: true)
    browser.post("/users/sign_in", params: { user: { email: user.email, password: "password" } })
    # CapHive support always answers the code step (M8)
    if browser.response.location.to_s.include?("/two_factor/new")
      user.reload
      travel(31.seconds) if user.consumed_timestep.to_i >= Time.now.to_i / 30
      browser.post("/two_factor", params: { otp_code: user.current_otp })
    end
    expect(browser.response).to be_redirect, "#{key} could not sign in"
    expect(browser.response.location.to_s).not_to include("/users/sign_in"), "#{key} could not sign in"
    @bdc_signed_in[key] = true
  end

  # A request as the person; the answer (after following redirects for a page) is kept for the Then steps
  def bdc_request(key, verb, path, params: {})
    bdc_sign_in(key)
    bdc_follow(bdc_browser(key), verb, path, params)
  end

  # A request through the investor's emailed magic link (no sign-in)
  def bdc_magic_request(email, kyc, verb, path, params: {})
    signed_id = InvestorKyc.signed_id_for_user(kyc, bdc_contact(email), expires_in: 30.days)
    bdc_follow(bdc_browser("magic:#{email}", fresh: true), verb, path, params.merge(signed_id:))
  end

  def bdc_follow(browser, verb, path, params)
    browser.public_send(verb, path, params:)
    @bdc_last_response = browser.response
    @bdc_last_flash = browser.request.flash.to_h
    3.times do
      break unless browser.response.redirect?

      browser.follow_redirect!
    end
    @bdc_last_page = browser.response.body
    @bdc_last_status = browser.response.status
    browser.response
  end

  def bdc_page
    Capybara.string(@bdc_last_page || raise("no page opened yet"))
  end

  def bdc_page_text
    bdc_page.text.squish
  end

  # Bearer-token API, the same client the API features use (api_json_steps.rb)
  def bdc_api(key, verb, path, body = nil)
    @bdc_api_clients ||= {}
    client = @bdc_api_clients[key] ||= begin
      user = key.include?("@") ? bdc_contact(key) : bdc_user(key)
      token = Devise::Api::Token.create!(resource_owner: user, access_token: Devise::Api::Token.generate_uniq_access_token(user),
                                         refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user), expires_in: 1.day.to_i)
      ApiJsonClient.new.tap { |c| c.access_token = token.access_token }
    end
    @bdc_api_response = client.call(verb, path, body&.to_json)
  end

  # ── KYC form values ───────────────────────────────────────────────────────

  # A table of | field | value | → the KYC's form params (custom fields by their label go to properties)
  def bdc_attrs(kyc, table)
    table.raw.each_with_object({}) do |(field, value), attrs|
      column = BankDetailChangeWorld::BDC_FIELDS[field]
      value = nil if value == "(blank)"
      if column
        attrs[column] = value
      else
        # The KYC form posts every custom field it shows: the stored values, with the scenario's changes
        key = bdc_custom_field_key(kyc, field)
        (attrs["properties"] ||= (kyc.json_fields || {}).dup)[key] = value
      end
    end
  end

  # A custom field of the KYC's form, by its label
  def bdc_custom_field_key(kyc, label)
    field = FormCustomField.find_by(form_type_id: kyc.form_type_id, label:)
    expect(field).to be_present, "no custom field labelled #{label} on #{kyc.full_name}'s form"
    field.name
  end

  def bdc_param_key(kyc)
    kyc.class.model_name.param_key
  end

  # The KYC form's save, as the person (PATCH /investor_kycs/:id)
  def bdc_save_kyc(key, kyc, attrs, extra = {})
    bdc_request(key, :patch, "/investor_kycs/#{kyc.id}", params: { bdc_param_key(kyc) => attrs }.merge(extra))
  end

  # ── imports ───────────────────────────────────────────────────────────────

  # One investor KYC import row from the KYC as it is now, with the scenario's changes
  def bdc_import_row(kyc, changes)
    row = { "Stakeholder" => kyc.investor.investor_name, "Investing Entity" => kyc.full_name, "Pan/Tax Id" => kyc.PAN,
            "Address" => kyc.address, "Correspondence Address" => kyc.corr_address,
            "Kyc Type" => kyc.individual? ? "Individual" : "Non Individual", "Date Of Birth" => kyc.birth_date&.iso8601,
            "Bank Name" => kyc.bank_name, "Branch Name" => kyc.bank_branch, "Bank Account Number" => kyc.bank_account_number,
            "Account Type" => kyc.bank_account_type, "Ifsc Code" => kyc.ifsc_code, "Verified" => nil, "Update Only" => "Yes",
            "Send Kyc Form To User" => "No", "Investor Signatory Emails" => kyc.esign_emails,
            "Agreement Committed Amount" => nil, "Agreement Unit Type" => nil, "Form Tag" => nil }
    custom = {}
    changes.each do |header, value|
      value = nil if value == "(blank)"
      if row.key?(header)
        row[header] = value
      else
        # A custom field column is headed by its label (ImportUtil#setup_custom_fields)
        custom[header] = value
      end
    end
    row.merge(custom)
  end

  # The import as the import job runs it (ApplicationJob restores Current.user = the uploader)
  def bdc_import(first, rows)
    headers = rows.first.keys
    path = Rails.root.join("tmp", "bdc_kyc_import_#{SecureRandom.hex(4)}.xlsx")
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: "Sheet1") do |sheet|
      sheet.add_row(headers)
      rows.each { |row| sheet.add_row(headers.map { |h| row[h] }, types: headers.map { :string }) }
    end
    package.serialize(path.to_s)
    user = bdc_user(first)
    upload = ImportUpload.create!(entity: user.entity, owner: user.entity, import_type: "InvestorKyc",
                                  name: "KYC import", user_id: user.id, import_file: File.open(path))
    bdc_as(first) { ImportUploadJob.perform_now(upload.id) }
    File.delete(path)
    @bdc_import = upload.reload
    @bdc_import_rows = bdc_import_results(@bdc_import)
  end

  # The results sheet: every data row's status and detail (the two columns after the row's own)
  def bdc_import_results(upload)
    file = upload.import_results&.download
    return [] unless file

    sheet = Roo::Spreadsheet.open(file.path, extension: :xlsx)
    width = sheet.row(1).compact.size
    (2..sheet.last_row).map do |i|
      cells = sheet.row(i)
      { status: cells[width].to_s, detail: cells[width + 1].to_s }
    end
  end

  # ── mail ──────────────────────────────────────────────────────────────────

  def bdc_mails_to(email, subject_part = nil)
    ActionMailer::Base.deliveries.select do |mail|
      Array(mail.to).include?(email) && (subject_part.nil? || mail.subject.to_s.include?(subject_part))
    end
  end

  def bdc_mail_text(mail)
    part = mail.html_part || mail.text_part || mail
    Capybara.string(part.decoded).text.squish
  end
end
World(BankDetailChangeWorld)

# Every scenario starts on "today" (09/11/2026 10:00) and ends back in real time
Before("@bank_detail_change") do
  travel_to BankDetailChangeWorld::TODAY
end

After("@bank_detail_change") do
  travel_back
end

# ── Setup ────────────────────────────────────────────────────────────────────

Given("the KYC {string} exists") do |name|
  @investor_kyc = bdc_kyc(name)
  @entity = @investor_kyc.entity
end

# "unverified by Meera": UnVerify's state (submitted, not verified); Bank Verified stays as it was
Given("the KYC {string} is unverified") do |name|
  kyc = bdc_kyc(name)
  kyc.update_columns(verified: false, verified_by_id: nil, submission_status: "completed", completed_by_investor: true)
  @investor_kyc = kyc.reload
  @entity = kyc.entity
end

Given("the KYC {string} is already verified") do |name|
  kyc = bdc_kyc(name)
  approver = BankDetailChangeWorld::BDC_KYCS.fetch(name)[:verified_by] || "Ravi"
  kyc.update_columns(verified: true, verified_by_id: bdc_user(approver).id, submission_status: "verified",
                     completed_by_investor: true)
  @investor_kyc = kyc.reload
  @entity = kyc.entity
end

# Sent to the investor to fill in (the magic link works only before submission)
Given("the KYC {string} was sent to the investor") do |name|
  kyc = bdc_kyc(name)
  kyc.update_columns(verified: false, verified_by_id: nil, submission_status: "link_sent", completed_by_investor: false)
  @investor_kyc = kyc.reload
  @entity = kyc.entity
end

Given("the KYC {string} starts with Bank Verified {word}") do |name, state|
  bdc_kyc(name).update_columns(bank_verified: state == "on")
end

Given("the bank check of {string} last said {string}") do |name, status|
  bdc_kyc(name).update_columns(bank_verification_status: status)
end

Given("the person {string} exists") do |first|
  bdc_user(first)
end

# H3 / §6 — the penny drop returns this name; "with a provider match" = Digio's own fuzzy match said yes
Given("the bank check returns {string} with a provider match") do |name|
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response(name:, fuzzy: true))
end

Given("the bank check returns {string} without a provider match") do |name|
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response(name:, fuzzy: false))
end

# H3 — hold the bank check so the moment straight after the save can be seen; "the held bank check runs" runs it
Given("the bank check is held until it is run") do
  @bdc_held_bank_checks = []
  allow(VerifyBankJob).to receive(:perform_now) { |**kwargs| @bdc_held_bank_checks << kwargs }
end

When("the held bank check runs") do
  expect(@bdc_held_bank_checks).not_to be_empty, "no bank check was started"
  RSpec::Mocks.space.proxy_for(VerifyBankJob).reset
  @bdc_held_bank_checks.each { |kwargs| VerifyBankJob.perform_now(**kwargs) }
end

# E10 — the firm's investor KYC journey, seeded before the KYC exists (so the KYC is assigned to it), walked to Verify
# KYC by Ravi with the steps the journey features use
Given("the investor KYC journey of the KYC {string} has reached Verify KYC") do |name|
  firm = bdc_firm(BankDetailChangeWorld::BDC_KYCS.fetch(name)[:firm])
  @entity = firm
  @user = bdc_user("Ravi")
  InvestorKycJourneySetup.call(entity: firm)
  @investor_kyc = bdc_kyc(name)
  # A KYC created before the journey was seeded (E61: by the distribution's setup) is assigned to it now
  WorkflowAutoAssignmentService.call(workflowable: @investor_kyc) unless @investor_kyc.workflow_instances.exists?
  @investor_kyc.update_columns(verified: false, verified_by_id: nil, submission_status: "not_sent", completed_by_investor: false)
  step "the KYC is at Verify KYC with my review and sign-off"
end

# Ends at the page after the redirect, so the Then steps can read the flash / note
When("{string} verifies the KYC {string} from its page") do |key, name|
  kyc = bdc_kyc(name)
  expect(kyc.verified).to be(false), "#{name} is already verified"
  bdc_request(key, :put, "/investor_kycs/#{kyc.id}/toggle_verified")
end

When("{string} unverifies the KYC {string} from its page") do |key, name|
  kyc = bdc_kyc(name)
  expect(kyc.verified).to be(true), "#{name} is not verified"
  bdc_request(key, :put, "/investor_kycs/#{kyc.id}/toggle_verified")
end

# ── Saving a KYC ─────────────────────────────────────────────────────────────

When("{string} saves the KYC {string} with:") do |first, name, table|
  kyc = bdc_kyc(name)
  bdc_save_kyc(first, kyc, bdc_attrs(kyc, table))
end

# X1, X5 — the same save with the model's validations on (the form's interim-save switch; fund users' saves
# otherwise skip them, see Changed during the build)
When("{string} saves the KYC {string} with validation and:") do |first, name, table|
  kyc = bdc_kyc(name)
  bdc_save_kyc(first, kyc, bdc_attrs(kyc, table), validate: "true")
end

When("{string} sends the KYC {string} over the API with:") do |key, name, table|
  kyc = bdc_kyc(name)
  bdc_api(key, :patch, "/investor_kycs/#{kyc.id}.json", { bdc_param_key(kyc) => bdc_attrs(kyc, table) })
end

When("the investor {string} submits the KYC {string} through the emailed link with:") do |email, name, table|
  kyc = bdc_kyc(name)
  bdc_magic_request(email, kyc, :patch, "/investor_kycs/#{kyc.id}", params: { bdc_param_key(kyc) => bdc_attrs(kyc, table) })
end

When("{string} saves the Compare CKYC\\/KRA form of the KYC {string} with:") do |first, name, table|
  kyc = bdc_kyc(name)
  attrs = bdc_attrs(kyc, table).merge("id" => kyc.id, "PAN" => kyc.PAN, "investor_id" => kyc.investor_id,
                                      "entity_id" => kyc.entity_id, "kyc_type" => kyc.kyc_type)
  bdc_request(first, :post, "/investor_kycs/compare_kyc_datas",
              params: { "investor_kyc" => attrs, "commit" => "Continue without CKYC/KRA" })
end

When("{string} imports an Update Only row for the KYC {string} with:") do |first, name, table|
  kyc = bdc_kyc(name)
  bdc_import(first, [bdc_import_row(kyc, table.raw.to_h)])
end

When("{string} imports a new KYC {string} for the investor {string} with:") do |first, name, investor_name, table|
  firm = bdc_user(first).entity
  investor_entity = Entity.find_by(name: investor_name) || FactoryBot.create(:entity, name: investor_name, entity_type: "Investor")
  Investor.find_by(entity_id: firm.id, investor_entity_id: investor_entity.id) ||
    FactoryBot.create(:investor, entity: firm, investor_entity:, investor_name:)
  row = { "Stakeholder" => investor_name, "Investing Entity" => name, "Pan/Tax Id" => "AAAPN9999N",
          "Address" => "1 MG Road, Bengaluru", "Correspondence Address" => nil, "Kyc Type" => "Individual",
          "Date Of Birth" => "1985-01-01", "Bank Name" => "HDFC Bank", "Branch Name" => "MG Road",
          "Bank Account Number" => nil, "Account Type" => "Savings Account", "Ifsc Code" => nil, "Verified" => nil,
          "Update Only" => "No", "Send Kyc Form To User" => "No", "Investor Signatory Emails" => nil,
          "Agreement Committed Amount" => nil, "Agreement Unit Type" => nil, "Form Tag" => nil }
  bdc_import(first, [row.merge(table.raw.to_h)])
end

# E5 — Document Checks read the value from the cancelled cheque; the person clicks "Use document value"
When("{string} uses the document value {string} for {string} on the KYC {string}") do |first, value, field, name|
  kyc = bdc_kyc(name)
  column = BankDetailChangeWorld::BDC_FIELDS[field] || bdc_custom_field_key(kyc, field)
  # Document Checks is switched on for the firm (DocCheckResultPolicy#enabled?)
  kyc.entity.permissions.set(:enable_doc_llm_validation)
  kyc.entity.save!(validate: false)
  run = DocCheckRun.create!(entity: kyc.entity, record: kyc, user: bdc_user(first), status: "done", current: true,
                            started_at: Time.current, finished_at: Time.current, counts: { "attention" => 1 })
  result = run.doc_check_results.create!(entity: kyc.entity, document_name: "Cancelled Cheque", look_for: field,
                                         action: "compare", field_name: column, outcome: "mismatch", doc_value: value,
                                         record_value: kyc.json_fields&.dig(column) || kyc.try(column))
  bdc_request(first, :patch, "/doc_check_results/#{result.id}/use_document_value")
end

# E6, E18 — the AI extraction agent ("always overwrite", a rule reading the bank field from the cheque) writes the
# value; "as <name>" is the person who started it, "with nobody behind it" a job with no acting user
When("the AI extraction writes {string} to {string} on the KYC {string} as {string}") do |value, field, name, first|
  bdc_run_extraction(value, field, name, first)
end

When("the AI extraction writes {string} to {string} on the KYC {string} with nobody behind it") do |value, field, name|
  bdc_run_extraction(value, field, name, nil)
end

def bdc_run_extraction(value, field, name, first)
  kyc = bdc_kyc(name)
  column = BankDetailChangeWorld::BDC_FIELDS[field] || bdc_custom_field_key(kyc, field)
  agent = SupportAgent.find_by(entity: kyc.entity, agent_type: "KycDocExtractorAgent") ||
          FactoryBot.create(:support_agent, entity: kyc.entity, agent_type: "KycDocExtractorAgent", enabled: true,
                                            name: "KYC Doc Extractor", llm_model: "gpt-4o", json_fields: {})
  agent.update!(json_fields: { "overwrite_mode" => "always",
                               "extraction_rules" => { kyc.form_type_id.to_s => [{ "doc_label" => "Cancelled Cheque",
                                                                                   "prompt" => "Read the field",
                                                                                   "target_field" => column }] } })
  folder = kyc.entity.folders.first_or_create!(name: "KYC Documents", folder_type: :regular)
  FactoryBot.create(:document, owner: kyc, name: "Cancelled Cheque", entity: kyc.entity, folder:,
                               user: bdc_user(first || "Ravi"))
  # The model answers with the value for every field it is asked about
  fake_chat = double("llm_chat")
  allow(fake_chat).to receive(:ask) { |prompt, **_| prompt.scan(/^(\w+):/).flatten.index_with { value }.to_json }
  allow(LlmService).to receive(:ruby_llm_chat).and_return(fake_chat)
  run = -> { KycDocExtractorAgent.call(support_agent_id: agent.id, target: InvestorKyc.find(kyc.id)) }
  first ? bdc_as(first) { run.call } : Current.set(user: nil) { run.call }
end

# ── KYC state ────────────────────────────────────────────────────────────────

Then("the KYC {string} has Bank Verified {word}") do |name, state|
  kyc = bdc_kyc(name)
  expect(kyc.bank_verified).to eq(state == "on"), "bank_verified=#{kyc.bank_verified} status=#{kyc.bank_verification_status.inspect}"
end

Then("the KYC {string} is verified") do |name|
  kyc = bdc_kyc(name)
  expect([kyc.verified, kyc.submission_status]).to eq([true, "verified"])
end

Then("the KYC {string} is not verified") do |name|
  kyc = bdc_kyc(name)
  expect(kyc.verified).to be(false), "submission_status=#{kyc.submission_status}"
  expect(kyc.submission_status).not_to eq("verified")
end

Then("the KYC {string} has {string} {string}") do |name, field, value|
  kyc = bdc_kyc(name)
  column = BankDetailChangeWorld::BDC_FIELDS[field]
  actual = column ? kyc.public_send(column) : kyc.json_fields[bdc_custom_field_key(kyc, field)]
  expect(actual.to_s).to eq(value)
end

Then("the KYC {string} keeps its bank check status {string}") do |name, status|
  expect(bdc_kyc(name).bank_verification_status).to eq(status)
end

Then("the KYC {string} has no bank check result") do |name|
  kyc = bdc_kyc(name)
  expect([kyc.bank_verification_status, kyc.bank_verification_response.presence]).to eq([nil, nil])
end

Then("the KYC {string} has the bank check response {string}") do |name, text|
  expect(bdc_kyc(name).bank_verification_response.to_s).to include(text)
end

Then("the KYC {string} has no bank check response mentioning {string}") do |name, text|
  expect(bdc_kyc(name).bank_verification_response.to_s).not_to include(text)
end

Then("the KYC {string} has PAN verification status {string}") do |name, status|
  expect(bdc_kyc(name).pan_verification_status.to_s).to eq(status)
end

# ── Pages, responses, imports ────────────────────────────────────────────────

When("{string} opens the KYC {string}") do |key, name|
  bdc_request(key, :get, "/investor_kycs/#{bdc_kyc(name).id}")
end

When("{string} opens the edit page of the KYC {string}") do |key, name|
  bdc_request(key, :get, "/investor_kycs/#{bdc_kyc(name).id}/edit")
end

Then("the edit page has no Bank Verified box") do
  expect(@bdc_last_status).to eq(200)
  expect(bdc_page).to have_no_css("#bank_verified_box", visible: :all)
  expect(bdc_page).to have_no_css("input[name$='[bank_verified]'][type=checkbox]", visible: :all)
end

Then("the edit page has a Bank Verified box saying {string}") do |tooltip|
  expect(@bdc_last_status).to eq(200)
  box = bdc_page.find("#bank_verified_box", visible: :all)
  expect(box).to have_css("input[name$='[bank_verified]'][type=checkbox]", visible: :all)
  expect(box.find("i.ti-info-circle", visible: :all)["title"]).to include(tooltip)
end

Then("the KYC page says {string}") do |text|
  expect(bdc_page_text).to include(text)
end

Then("the KYC page does not say {string}") do |text|
  expect(bdc_page_text).not_to include(text)
end

Then("the save is refused with the form error {string}") do |text|
  expect(@bdc_last_status).to eq(422)
  expect(bdc_page_text).to include(text)
end

Then("the KYC API answers {int}") do |status|
  expect(@bdc_api_response.status).to eq(status), @bdc_api_response.body.to_s.first(500)
end

Then("the import row says {string}") do |status|
  expect(@bdc_import_rows.pluck(:status)).to eq([status]), @bdc_import_rows.inspect
end

Then("the import row says {string} with {string}") do |status, detail|
  expect(@bdc_import_rows.pluck(:status)).to eq([status]), @bdc_import_rows.inspect
  expect(@bdc_import_rows.first[:detail]).to include(detail)
end

Then("the KYC {string} journey moved back with {string}") do |name, note|
  instance = journey_instance(bdc_kyc(name))
  result = instance.step_result(instance.current_step_position) || {}
  expect(result["regressed"]).to be(true), instance.step_results.inspect
  expect(result["regressed_reason"].to_s).to include(note), instance.step_results.inspect
end

# ── §3 Change record and the KYC page note ───────────────────────────────────

# Table rows: status | maker | side | source | account ("4821 → 7310") | IFSC ("HDFC0001234 → ICIC0004567")
Then("the latest bank change of the KYC {string} is:") do |name, table|
  change = BankDetailChange.where(investor_kyc_id: bdc_kyc(name).id).order(:id).last
  expect(change).to be_present, "no bank change recorded for #{name}"
  table.raw.each do |field, value|
    actual = case field
             when "status" then change.status
             when "maker" then change.maker_name
             when "side" then change.changed_by_side
             when "source" then change.source
             when "account" then "#{change.old_account_last4 || 'none'} → #{change.new_account_last4 || 'none'}"
             when "IFSC" then "#{change.old_ifsc} → #{change.new_ifsc}"
             when "confirmed by" then change.confirmed_by&.full_name
             when "only approver" then change.only_approver ? "yes" : "no"
             when "custom fields" then change.custom_field_lines.join("; ")
             else raise "unknown bank change field #{field}"
             end
    expect(actual.to_s).to eq(value), "#{field}: #{change.attributes.except('investor_recipient_ids').inspect}"
  end
end

Then("the KYC {string} has no bank change") do |name|
  expect(BankDetailChange.where(investor_kyc_id: bdc_kyc(name).id)).not_to exist
end

Then("the KYC {string} has {int} bank changes, the first {string}") do |name, count, status|
  changes = BankDetailChange.where(investor_kyc_id: bdc_kyc(name).id).order(:id).to_a
  expect(changes.size).to eq(count)
  expect(changes.first.status).to eq(status)
  expect(changes.count(&:awaiting?)).to be <= 1
end

# E23 — no column of any change row holds a full account number
Then("no bank change record of the KYC {string} holds {string} or {string}") do |name, first, second|
  BankDetailChange.where(investor_kyc_id: bdc_kyc(name).id).find_each do |change|
    stored = change.attributes.values.join(" ")
    expect(stored).not_to include(first)
    expect(stored).not_to include(second)
  end
end

def bdc_note
  bdc_page.find("[data-bank-change-note]", visible: :all)
end

Then("the bank change note says {string}") do |text|
  expect(@bdc_last_status).to eq(200)
  expect(bdc_note.text.squish).to include(text)
end

# The ⓘ next to the note: what it means and what to do (U.1)
Then("the bank change note explains {string}") do |text|
  tooltip = bdc_note.all("i.ti-info-circle", visible: :all).map { |i| i["title"] || i["data-bs-title"] }.join(" ")
  expect(tooltip.squish).to include(text)
end

Then("the KYC page has no bank change note") do
  expect(@bdc_last_status).to eq(200)
  expect(bdc_page).to have_no_css("[data-bank-change-note]", visible: :all)
  expect(bdc_page_text).not_to include("Bank details changed on")
end

Then("the Bank Verified badge says {string}") do |text|
  expect(bdc_page.find("[data-bank-verified-badge]", visible: :all).text.squish).to include(text)
end

Then("the Bank Verified badge explains {string}") do |text|
  expect(bdc_page.find("[data-bank-verified-badge]", visible: :all)["title"].to_s).to include(text)
end

# E64, E66 — an edit of a custom field is in the KYC's audit trail (as today): some audited change of the column
# holds the value
Then("the audit trail of the KYC {string} records {string} in {string}") do |name, value, column|
  changes = bdc_kyc(name).audits.order(:id).filter_map { |audit| audit.audited_changes[column] }
  expect(changes.join(" ")).to include(value)
end

# E21 — the KYC's own audit trail (KYC Actions › Audit Trail lists these audits) keeps the old full value
Then("the audit trail of the KYC {string} shows {string} changed from {string}") do |name, column, old|
  changes = bdc_kyc(name).audits.order(:id).filter_map { |audit| audit.audited_changes[column] }
  expect(changes.map { |change| Array(change).first.to_s }).to include(old)
end

# ── §4 Change emails ─────────────────────────────────────────────────────────

BDC_SUBJECTS = /Your bank details with .* were changed|Bank details changed for .* a second approver must verify|Account update at/

def bdc_recipient_email(key)
  key.include?("@") ? key : bdc_user(key).email
end

def bdc_change_mails_to(key)
  bdc_mails_to(bdc_recipient_email(key)).select { |mail| mail.subject.to_s.match?(BDC_SUBJECTS) }
end

Then("{string} receives {int} email {string}") do |key, count, subject|
  mails = bdc_mails_to(bdc_recipient_email(key), subject)
  expect(mails.size).to eq(count), "#{key} got: #{bdc_mails_to(bdc_recipient_email(key)).map(&:subject).inspect}"
  @bdc_mail = mails.last
end

Then("{string} receives no bank change email") do |key|
  expect(bdc_change_mails_to(key)).to be_empty
end

Then("no bank change email was sent") do
  expect(ActionMailer::Base.deliveries.map(&:subject).grep(BDC_SUBJECTS)).to be_empty
end

Then("that email says {string}") do |text|
  expect(bdc_mail_text(@bdc_mail)).to include(text)
end

Then("that email does not say {string}") do |text|
  expect(bdc_mail_text(@bdc_mail)).not_to include(text)
end

Then("that email has a {string} link to the KYC {string}") do |label, name|
  part = @bdc_mail.html_part || @bdc_mail
  link = Capybara.string(part.decoded).find_link(label)
  expect(link[:href]).to include("/investor_kycs/#{bdc_kyc(name).id}")
  expect(link[:href]).not_to include("signed_id")
end

Then("{string} has a bell notification {string}") do |first, text|
  messages = Noticed::Notification.where(recipient: bdc_user(first)).includes(:event).map(&:message)
  expect(messages.join(" | ")).to include(text)
end

# E25 — the emails wait (as they do in Sidekiq) until "the held bank change emails are sent"
Given("the bank change emails are held until they are sent") do
  @bdc_held_changes = []
  allow(BankDetailChangeNotifyJob).to receive(:perform_later) { |id| @bdc_held_changes << id }
end

When("a minute later the contact {string} is approved for the investor of {string}") do |email, name|
  travel 1.minute
  bdc_add_contact(bdc_kyc(name).investor, email, at: Time.current)
end

When("a minute later the held bank change emails are sent") do
  travel 1.minute
  expect(@bdc_held_changes).not_to be_empty, "no bank change email job was queued"
  RSpec::Mocks.space.proxy_for(BankDetailChangeNotifyJob).reset
  @bdc_held_changes.each { |id| BankDetailChangeNotifyJob.perform_now(id) }
end

When("the bank change email job of the KYC {string} runs again") do |name|
  change = BankDetailChange.where(investor_kyc_id: bdc_kyc(name).id).order(:id).last
  BankDetailChangeNotifyJob.perform_now(change.id)
end

Given("Horizon Capital rewords the bank change email as {string} with {string}") do |subject, body|
  firm = bdc_firm("Horizon Capital")
  CustomNotification.create!(entity: firm, owner: firm, for_type: "InvestorKyc", subject:, body:,
                             email_method: "notify_bank_details_changed")
end

# X6 — nobody at the investor can be emailed about the KYC
Given("the investor of {string} has no contact for KYC emails") do |name|
  bdc_kyc(name).investor.investor_accesses.update_all(approved: false)
end

# ── §5 Second person ─────────────────────────────────────────────────────────

# "The next day" (10/11/2026): a jump in time outlives the session cookie, so everyone signs in again
Given("the next day comes") do
  travel 1.day
  @bdc_signed_in = {}
end

Given("the user {string} is no longer active") do |first|
  bdc_user(first).update_columns(active: false)
end

Given("the KYC {string} has full bank details") do |name|
  bdc_kyc(name).update_columns(bank_account_number: "30200011112222", ifsc_code: "KKBK0000123", bank_name: "Kotak Bank",
                               bank_branch: "MG Road", bank_account_type: "Savings Account")
end

Then("{string} is told {string}") do |_key, text|
  expect(@bdc_last_flash.values.join(" ")).to include(text), "flash: #{@bdc_last_flash.inspect} status #{@bdc_last_response&.status}"
end

def bdc_popup
  bdc_page.find("#verifyBankChangeModal", visible: :all)
end

# H9 — the person opens the KYC, the popup is there, and they click its "Verify KYC" (the popup's own form)
When("{string} confirms the Verify popup of the KYC {string}") do |key, name|
  step %("#{key}" opens the KYC "#{name}")
  form = bdc_popup.find("form", visible: :all)
  expect(form.find("#verify_bank_change_submit", visible: :all).text.squish).to include("Verify KYC")
  intent = form.find("input[name=intent]", visible: :all).value
  bdc_request(key, :put, form[:action], params: { intent: })
end

# X12 — the same form posted a second time (a double click)
When("{string} submits the Verify popup of the KYC {string} again") do |key, name|
  bdc_request(key, :put, "/investor_kycs/#{bdc_kyc(name).id}/toggle_verified", params: { intent: "verify" })
end

Then("the Verify button opens the popup {string}") do |title|
  button = bdc_page.find("#investor_kyc_toggle_verified_btn", visible: :all)
  expect(button["data-bs-target"]).to eq("#verifyBankChangeModal")
  expect(bdc_popup.find(".modal-title", visible: :all).text.squish).to eq(title)
end

def bdc_popup_card(title)
  bdc_popup.all("[data-verify-card]", visible: :all).find { |card| card.find(".fw-semibold", visible: :all).text.squish.start_with?(title) }
end

Then("the Verify popup shows the card {string} saying {string}") do |title, text|
  card = bdc_popup_card(title)
  expect(card).to be_present, "cards: #{bdc_popup.all('[data-verify-card] .fw-semibold', visible: :all).map(&:text)}"
  expect(card.text.squish).to include(text)
end

Then("the Verify popup has no card {string}") do |title|
  expect(bdc_popup_card(title)).to be_nil
end

Then("the Verify popup has the buttons {string} and {string}") do |first, second|
  footer = bdc_popup.find(".modal-footer", visible: :all).text.squish
  expect(footer).to include(first)
  expect(footer).to include(second)
end

Then("the page has no Verify popup") do
  expect(@bdc_last_status).to eq(200)
  expect(bdc_page).to have_no_css("#verifyBankChangeModal", visible: :all)
end

# E32 — the button is disabled and its wrapper's tooltip says why and what to do instead (U.1)
Then("the page shows Verify greyed out saying {string}") do |text|
  wrapper = bdc_page.find("#investor_kyc_verify_blocked", visible: :all)
  expect(wrapper).to have_css("button#investor_kyc_toggle_verified_btn[disabled]", visible: :all)
  expect(wrapper.find("[data-bs-toggle=tooltip]", visible: :all)["title"]).to include(text)
end

# E37 — the bulk job as the KYC list's Bulk Actions › Verify starts it; its error list is what the user is emailed
When("{string} bulk-verifies the KYCs {string}") do |first, names|
  ids = names.split(",").map { |name| bdc_kyc(name.strip).id }
  job = InvestorKycsBulkActionJob.new
  bdc_as(first) { job.perform(ids, bdc_user(first).id, "verify") }
  @bdc_bulk_errors = job.instance_variable_get(:@error_msg)
end

Then("the bulk result lists {string} as {string}") do |name, message|
  row = @bdc_bulk_errors.find { |error| error[:id] == bdc_kyc(name).id }
  expect(row).to be_present, @bdc_bulk_errors.inspect
  expect(row[:msg]).to eq(message)
end

When("{string} sends a JSON Verify request for the KYC {string}") do |key, name|
  bdc_api(key, :put, "/investor_kycs/#{bdc_kyc(name).id}/toggle_verified.json")
end

Then("the KYC API error says {string}") do |text|
  expect(JSON.parse(@bdc_api_response.body)["error"]).to eq(text)
end

# ── §6 Bank check name rule ─────────────────────────────────────────────────

Given("the bank check finds no account and says {string}") do |error|
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response(verified: false, error_msg: error))
end

Given("the bank check answers {string}") do |raw|
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response(body: raw))
end

Given("the bank check must not be called") do
  expect_any_instance_of(KycVerify).not_to receive(:verify_bank)
end

# E53 — the provider is slow: while it checks …7310, Dev saves …9902 (the KYC form's save, through the model), so the
# check's answer arrives for an account the KYC no longer has
Given("the bank check of the account ending {string} matches but takes so long that {string} saves {string} meanwhile") do |last4, first, newer|
  world = self
  allow_any_instance_of(KycVerify).to receive(:verify_bank) do |_verify, full_name, account, _ifsc|
    if account.to_s.end_with?(last4)
      kyc = InvestorKyc.find_by!(full_name:)
      world.bdc_as(first) do
        kyc.bank_change_source = "screen"
        kyc.update!(bank_account_number: newer)
      end
    end
    world.send(:bank_response, name: full_name.upcase, fuzzy: true)
  end
end

When("the bank check of the KYC {string} runs again and returns {string} without a provider match") do |name, bank_name|
  allow_any_instance_of(KycVerify).to receive(:verify_bank).and_return(bank_response(name: bank_name, fuzzy: false))
  kyc = bdc_kyc(name)
  VerifyBankJob.perform_now(obj_class: kyc.class.name, obj_id: kyc.id)
end

# E55 — an offer in a Kestrel secondary sale, by the KYC's investor, with its own bank details
Given("a Kestrel secondary-sale offer by {string} with bank details") do |name|
  firm = bdc_firm("Kestrel Capital")
  investor = bdc_kyc(name).investor
  sale = FactoryBot.create(:secondary_sale, entity: firm, name: "Kestrel Secondary 2026")
  @bdc_offer = FactoryBot.build(:offer, entity: firm, secondary_sale: sale, investor:, user: bdc_user("Dev"),
                                        full_name: name, bank_account_number: "60200033330000", ifsc_code: "SBIN0001111")
  @bdc_offer.save!(validate: false)
end

When("the bank check of that offer runs") do
  VerifyBankJob.perform_now(obj_class: "Offer", obj_id: @bdc_offer.id)
end

Then("that offer is bank verified") do
  expect(@bdc_offer.reload.bank_verified).to be(true), @bdc_offer.bank_verification_status.inspect
end

# A browser (Capybara) session: the Verify popup opened by the page's Verify control, confirmed with "Verify KYC"
When("I confirm the bank change Verify popup") do
  within("#verifyBankChangeModal") do
    expect(page).to have_text("You are the second person")
    click_on "Verify KYC"
  end
end

# ── §7 Payout flags ──────────────────────────────────────────────────────────

# The firm's fund, with a commitment for each KYC's investor linked to the KYC, the distribution journeys seeded,
# and a distribution generating one payment per commitment (not yet emailed)
Given("Horizon Capital's {string} of {string} pays {string} and {string}") do |title, fund_name, first, second|
  firm = bdc_firm("Horizon Capital")
  @entity = firm
  CapitalDistributionJourneySetup.call(entity: firm)
  fund = Fund.find_by(entity: firm, name: fund_name) ||
         FactoryBot.create(:fund, entity: firm, name: fund_name, currency: "INR", unit_types: nil)
  [first, second].each do |name|
    kyc = bdc_kyc(name)
    commitment = FactoryBot.build(:capital_commitment, fund:, entity: firm, investor: kyc.investor, unit_type: nil,
                                                       folio_currency: "INR", orig_folio_committed_amount_cents: 1_000_000_000)
    result = CapitalCommitmentCreate.call(capital_commitment: commitment)
    expect(result).to be_success, commitment.errors.full_messages.to_s
    commitment.update_columns(investor_kyc_id: kyc.id)
  end
  # Meera works on this fund (she downloads its payments)
  AccessRight.find_or_create_by!(entity: firm, owner: fund, user_id: bdc_user("Meera").id) do |right|
    right.notify = false
    right.permissions = %i[create read update destroy]
  end
  dist = CapitalDistribution.new(entity: firm, fund:, title:, income_cents: 2_050_000_00, cost_of_investment_cents: 0,
                                 reinvestment_cents: 0, distribution_date: Date.new(2026, 11, 20), generate_payments: true)
  result = CapitalDistributionCreate.call(capital_distribution: dist)
  expect(result).to be_success, dist.errors.full_messages.to_s
  @bdc_distribution = dist.reload
  expect(@bdc_distribution.capital_distribution_payments.count).to eq(2)
end

def bdc_distribution(title)
  CapitalDistribution.find_by!(title:)
end

When("{string} opens the distribution page of {string}") do |key, title|
  bdc_request(key, :get, "/capital_distributions/#{bdc_distribution(title).id}")
end

def bdc_journey_warnings
  bdc_page.all(".journey-warning", visible: :all).map { |w| w.text.squish }
end

Then("the journey panel warns {string}") do |text|
  expect(@bdc_last_status).to eq(200)
  expect(bdc_journey_warnings.join(" | ")).to include(text)
end

Then("the journey panel has no warning {string}") do |text|
  expect(@bdc_last_status).to eq(200)
  expect(bdc_journey_warnings.join(" | ").downcase).not_to include(text.downcase)
end

Then("the journey panel is shown") do
  expect(bdc_page).to have_css("#capital_distribution_journey_card", visible: :all)
end

Given("the investors of {string} have been emailed") do |title|
  bdc_distribution(title).capital_distribution_payments.update_all(completed: true, notification_sent: true)
end

Given("Bina Shah's commitment to {string} is set to Skip Doc Gen") do |fund_name|
  commitment = CapitalCommitment.joins(:fund).find_by!(funds: { name: fund_name }, investor_kyc_id: bdc_kyc("Bina Shah").id)
  commitment.update_column(:json_fields, (commitment.json_fields || {}).merge("skip_doc_gen" => "Yes"))
end

# The readiness agent as its Run button runs it on one distribution (SupportAgentJob, single target with steps)
def bdc_run_readiness(first, title, checks)
  dist = bdc_distribution(title)
  toggles = DistributionReadinessAgent::CHECK_TOGGLES.keys.index_with { |key| checks.include?(key) ? "true" : "false" }
  agent = SupportAgent.find_by(entity: dist.entity, agent_type: "DistributionReadinessAgent") ||
          FactoryBot.create(:support_agent, entity: dist.entity, agent_type: "DistributionReadinessAgent", enabled: true,
                                            name: "Distribution Readiness", llm_model: "gpt-4o", json_fields: {})
  agent.update!(json_fields: toggles)
  user = bdc_user(first)
  bdc_as(first) do
    report = DistributionReadinessAgent.new.initialize_report_with_steps({}, model: dist, support_agent: agent, user_id: user.id)
    DistributionReadinessAgent.call(support_agent_id: agent.id, target: dist, user_id: user.id, entity_id: dist.entity_id,
                                    support_agent_report: report)
    @bdc_readiness = report.reload
  end
end

When("{string} runs the distribution readiness check on {string} with only the bank details check on") do |first, title|
  bdc_run_readiness(first, title, %w[check_bank_details])
end

When("{string} runs the distribution readiness check on {string} with the KYC and bank details checks on") do |first, title|
  bdc_run_readiness(first, title, %w[check_kyc check_bank_details])
end

When("{string} runs the distribution readiness check on {string} with only the KYC check on") do |first, title|
  bdc_run_readiness(first, title, %w[check_kyc])
end

def bdc_readiness_step(id)
  @bdc_readiness.json_fields["steps"].find { |step| step["id"] == id } || raise("no readiness step #{id}")
end

Then("the readiness step {string} is {string}") do |id, status|
  expect(bdc_readiness_step(id)["status"]).to eq(status), bdc_readiness_step(id).inspect
end

Then("the readiness step {string} is {string} with {string}") do |id, status, message|
  step_data = bdc_readiness_step(id)
  expect(step_data["status"]).to eq(status), step_data.inspect
  expect(step_data["message"].to_s).to include(message)
end

Then("the readiness step {string} is {string} listing {string} as {string}") do |id, status, name, reason|
  step_data = bdc_readiness_step(id)
  expect(step_data["status"]).to eq(status), step_data.inspect
  expect(Array(step_data["failed_records"])).to include(include("name" => name, "reason" => reason))
end

Then("the readiness step {string} is not run") do |id|
  expect(bdc_readiness_step(id)["status"]).to eq("pending")
end

When("{string} downloads the payments of {string}") do |first, title|
  dist = bdc_distribution(title)
  bdc_request(first, :get, "/capital_distribution_payments.xlsx", params: { capital_distribution_id: dist.id })
  expect(@bdc_last_status).to eq(200)
  path = Rails.root.join("tmp", "bdc_payments_#{SecureRandom.hex(4)}.xlsx")
  File.binwrite(path, @bdc_last_page)
  sheet = Roo::Spreadsheet.open(path.to_s, extension: :xlsx)
  @bdc_xlsx_headers = sheet.row(1)
  @bdc_xlsx_rows = (2..sheet.last_row).map { |i| @bdc_xlsx_headers.zip(sheet.row(i)).to_h }
  File.delete(path)
end

Then("the payments download's last column is {string}") do |header|
  expect(@bdc_xlsx_headers.last).to eq(header)
end

def bdc_xlsx_value(name)
  row = @bdc_xlsx_rows.find { |r| r["Investing Entity"] == name } || raise("no payment row for #{name}: #{@bdc_xlsx_rows.inspect}")
  row["Unconfirmed Bank Change"]
end

Then("the payments download shows {string} for {string} and nothing for {string}") do |date, first, second|
  expect(bdc_xlsx_value(first).to_s).to eq(date)
  expect(bdc_xlsx_value(second)).to be_blank
end

Then("the payments download shows nothing for {string} and nothing for {string}") do |first, second|
  expect(bdc_xlsx_value(first)).to be_blank
  expect(bdc_xlsx_value(second)).to be_blank
end

# E60 — the headers as they were before M14 (index.xlsx.axlsx), in order, then the new one
Then("the payments download's columns are the existing ones in order, then {string}") do |header|
  existing = ["Fund", "Investor", "Capital Distribution", "Folio Currency", "Payment Amount (Folio Currency)",
              "Face Value For Redemption", "Face Value For Redemption With Fees", "Reinvestment", "Reinvestment with Fees",
              "Income", "Income with Fees", "Expense with Fees", "Tax with Fees", "Percentage", "Units Quantity",
              "Gross Payable", "Net Payable", "Gross of Account Entries", "Net of Account Entries", "Payment Date",
              "Completed", "Folio No", "Bank Account", "IFSC", "Investing Entity", "PAN"]
  expect(@bdc_xlsx_headers.first(existing.size)).to eq(existing)
  expect(@bdc_xlsx_headers.last).to eq(header)
  expect(@bdc_xlsx_headers.count(header)).to eq(1)
end

# ── §8 Payout custom fields ──────────────────────────────────────────────────

BDC_FORMS = { "Individual" => "IndividualKyc", "Non-Individual" => "NonIndividualKyc", "Investor" => "Investor" }.freeze
BDC_KINDS = { "bank code" => "code", "account identifier" => "account" }.freeze
# The side panel's and Form Types › Edit's choice → the stored kind
BDC_PANEL_KINDS = { "Bank code" => "code", "Account identifier" => "account", "No" => "" }.freeze

def bdc_form_type(firm_name, form)
  FormType.find_by!(entity: bdc_firm(firm_name), name: BDC_FORMS.fetch(form))
end

def bdc_field(firm_name, form, label)
  FormCustomField.find_by!(form_type: bdc_form_type(firm_name, form), label:)
end

def bdc_add_field(form_type, label, name, field_type)
  FormCustomField.find_by(form_type:, name:) ||
    FormCustomField.create!(form_type:, label:, name:, field_type:, step: "two", position: form_type.form_custom_fields.count + 1)
end

# business-rules.md "Shared setup" (Phase 6): nothing marked at the start
Given("Horizon Capital's KYC forms have the SWIFT and IBAN custom fields") do
  firm = bdc_firm("Horizon Capital")
  individual = FormType.find_by!(entity: firm, name: "IndividualKyc")
  bdc_add_field(individual, "SWIFT Code", "swift_code", "TextField")
  bdc_add_field(individual, "IBAN", "iban_code", "TextField")
  bdc_add_field(individual, "Intermediary Bank Name", "intermediary_bank_name", "TextField")
  bdc_add_field(individual, "Foreign account?", "foreign_account", "CheckBox")
  bdc_add_field(individual, "Bank Address", "bank_address", "TextArea")
  bdc_add_field(FormType.find_by!(entity: firm, name: "NonIndividualKyc"), "SWIFT Code", "swift_code", "TextField")
  investor_form = FormType.find_or_create_by!(entity: firm, name: "Investor")
  bdc_add_field(investor_form, "Investor SWIFT", "investor_swift", "TextField")
end

def bdc_mark(firm_name, form, label, kind)
  field = bdc_field(firm_name, form, label)
  field.payout_field = kind
  field.save!
end

Given("{string} is marked as a bank code on the Individual KYC form") do |label|
  bdc_mark("Horizon Capital", "Individual", label, "code")
end

Given("{string} is marked as an account identifier on the Individual KYC form") do |label|
  bdc_mark("Horizon Capital", "Individual", label, "account")
end

Given("Kestrel Capital's Individual KYC form has {string} marked as a bank code") do |label|
  bdc_add_field(FormType.find_by!(entity: bdc_firm("Kestrel Capital"), name: "IndividualKyc"), label, "swift_code", "TextField")
  bdc_mark("Kestrel Capital", "Individual", label, "code")
end

Given("Solo Advisors' Individual KYC form has {string} marked as a bank code") do |label|
  bdc_add_field(FormType.find_by!(entity: bdc_firm("Solo Advisors"), name: "IndividualKyc"), label, "swift_code", "TextField")
  bdc_mark("Solo Advisors", "Individual", label, "code")
end

Given("the KYC {string} holds the SWIFT Code {string}") do |name, value|
  kyc = bdc_kyc(name)
  kyc.update_columns(json_fields: (kyc.json_fields || {}).merge("swift_code" => value))
end

Given("the KYC {string} has a blank {string}") do |name, label|
  kyc = bdc_kyc(name)
  kyc.update_columns(json_fields: (kyc.json_fields || {}).except(bdc_custom_field_key(kyc, label)))
end

# E66 — a SWIFT edit made the day before the field was marked (an ordinary audited save, as the form makes it)
Given("on 08\\/11\\/2026 {string} saved the KYC {string} with SWIFT Code {string}") do |first, name, value|
  travel_to(Time.zone.local(2026, 11, 8, 15)) do
    kyc = bdc_kyc(name)
    bdc_as(first) { kyc.update!(json_fields: kyc.json_fields.merge("swift_code" => value)) }
  end
end

Then("{string} on the {word} KYC form is a payout field of kind {string}") do |label, form, kind|
  expect(bdc_field("Horizon Capital", form, label).reload.payout_field).to eq(kind)
end

Then("{string} on the {word} KYC form is not a payout field") do |label, form|
  expect(bdc_field("Horizon Capital", form, label).reload.payout_field).to be_blank
end

Then("{string} on the Investor form is not a payout field") do |label|
  expect(bdc_field("Horizon Capital", "Investor", label).reload.payout_field).to be_blank
end

Then("{string} on the Individual KYC form has the max length {int}") do |label, length|
  expect(bdc_field("Horizon Capital", "Individual", label).reload.vr_max_length.to_i).to eq(length)
end

# ── the custom fields side panel (form_type_fields) ──

When("{string} opens the custom fields side panel of the KYC {string}") do |key, name|
  # record_type as the KYC page's icon sends it: the KYC's own class (IndividualKyc)
  kyc = bdc_kyc(name)
  bdc_request(key, :get, "/form_type_fields/settings", params: { record_type: kyc.class.name, record_id: kyc.id })
end

def bdc_panel_row(label)
  bdc_page.all("[data-form-type-fields-row]", visible: :all).find do |row|
    row.find("[data-form-type-fields-label]", visible: :all).value == label
  end || raise("no side panel row #{label}")
end

Then("the side panel row {string} offers the payout field choice {string}") do |label, tooltip|
  row = bdc_panel_row(label)
  expect(row).to have_css("select[data-form-type-fields-payout]", visible: :all)
  expect(row.find("[data-payout-flag]", visible: :all)["title"]).to include(tooltip)
end

Then("the side panel row {string} offers no payout field choice") do |label|
  expect(bdc_panel_row(label)).to have_no_css("select[data-form-type-fields-payout]", visible: :all)
end

Then("the side panel row {string} shows the payout icon") do |label|
  expect(bdc_panel_row(label)).to have_css("[data-payout-flag].on i.ti-building-bank", visible: :all)
end

Then("the side panel row {string} is locked with {string}") do |label, tooltip|
  row = bdc_panel_row(label)
  expect(row.find("[data-payout-locked]", visible: :all)["title"]).to include(tooltip)
  # the kind may still switch (code ↔ account), but there is no "No"
  expect(row).to have_no_css("select[data-form-type-fields-payout] option[value='']", visible: :all)
end

Then("the side panel row {string} has no remove button") do |label|
  expect(bdc_panel_row(label)).to have_no_css(".grid-columns-remove", visible: :all)
end

# The panel's Save, as its Stimulus controller sends it: every unlocked row, by id, with its flags; the table names
# the payout choice per field (by label)
def bdc_panel_items(form_type, changes, remove: [])
  form_type.form_custom_fields.not_regulatory.order(:position).map do |field|
    item = { "id" => field.id, "label" => field.human_label, "help_text" => field.help_text.to_s,
             "required" => field.required, "read_only" => field.read_only, "internal" => field.internal }
    item["payout_field"] = BDC_PANEL_KINDS.fetch(changes[field.label]) if changes.key?(field.label)
    item["_destroy"] = true if remove.include?(field.label)
    item
  end
end

def bdc_panel_save(key, kyc, changes, remove: [])
  items = bdc_panel_items(kyc.form_type, changes, remove:)
  bdc_request(key, :patch, "/form_type_fields/save",
              params: { record_type: kyc.class.name, record_id: kyc.id, fields: items.to_json })
end

When("{string} saves the custom fields side panel of the KYC {string} with:") do |key, name, table|
  bdc_panel_save(key, bdc_kyc(name), table.raw.to_h)
end

When("{string} removes {string} in the custom fields side panel of the KYC {string}") do |key, label, name|
  bdc_panel_save(key, bdc_kyc(name), {}, remove: [label])
end

# E77 — CapHive support signs in (two-factor) and uses Login as on the client's admin
When("CapHive support {string} saves the custom fields side panel of the KYC {string} as {string} with:") do |support, name, client, table|
  bdc_firm("Horizon Capital").tap do |firm|
    firm.permissions.set(:enable_support)
    firm.save!(validate: false)
  end
  FactoryBot.create(:support_client_mapping, user: bdc_user(support), entity: bdc_firm("Horizon Capital"), enabled: true,
                                             enable_user_login: true, end_date: Date.new(2027, 12, 31))
  bdc_request(support, :post, "/users/#{bdc_user(client).id}/login_as")
  expect(@bdc_last_flash.values.join(" ")).to include("Signed in as #{bdc_user(client).full_name}")
  bdc_panel_save(support, bdc_kyc(name), table.raw.to_h)
end

When("{string} saves the custom fields side panel of Horizon's Individual KYC form with:") do |key, table|
  form_type = bdc_form_type("Horizon Capital", "Individual")
  items = bdc_panel_items(form_type, table.raw.to_h)
  bdc_request(key, :patch, "/form_type_fields/save", params: { form_type_id: form_type.id, fields: items.to_json })
end

# The saved marker the panel's controller turns into the "… saved" notice and a page refresh (D16)
Then("the side panel says {string}") do |text|
  expect(@bdc_last_status).to eq(200)
  expect(bdc_page.find("[data-form-type-fields-saved]", visible: :all)["data-label"]).to eq(text)
end

Then("the side panel refuses with {string}") do |text|
  expect(@bdc_last_status).to eq(422)
  expect(bdc_page_text).to include(text)
end

Then("Omar's request is refused") do
  expect([302, 403, 404]).to include(@bdc_last_response.status), "status #{@bdc_last_response.status}"
  expect(@bdc_last_flash.values.join(" ") + @bdc_last_page.to_s).to match(/Access Denied|not found|denied/i)
end

# ── Form Types › Edit and Form Custom Fields ──

When("{string} opens Form Types › Edit of the Individual KYC form") do |key|
  bdc_request(key, :get, "/form_types/#{bdc_form_type('Horizon Capital', 'Individual').id}/edit")
end

Then("the field {string} has the payout field choice {string} selected") do |label, choice|
  field = bdc_field("Horizon Capital", "Individual", label)
  select = bdc_page.all("select[name$='[payout_field]']", visible: :all).find do |s|
    s[:name].include?("form_custom_fields_attributes") && s.ancestor("[data-fcf-key='#{field.id}']", visible: :all)
  end
  expect(select).to be_present
  expect(select.find("option[selected]", visible: :all).text).to eq(choice)
end

# The Form Types › Edit save with one field's settings changed (the other fields are sent as they are, by id)
def bdc_form_type_update(key, form_type, label, changes)
  attrs = {}
  form_type.form_custom_fields.order(:position).each_with_index do |field, i|
    row = { "id" => field.id, "name" => field.name, "label" => field.label, "field_type" => field.field_type,
            "position" => field.position }
    row.merge!(changes) if field.label == label
    attrs[i.to_s] = row
  end
  bdc_request(key, :patch, "/form_types/#{form_type.id}", params: { form_type: { form_custom_fields_attributes: attrs } })
end

When("{string} sets the payout field of {string} to {string} in Form Types › Edit of the {word} form") do |key, label, kind, form|
  bdc_form_type_update(key, bdc_form_type("Horizon Capital", form == "Investor" ? "Investor" : form), label, "payout_field" => kind)
end

When("{string} sets the payout field of {string} to {string} in Form Types › Edit of the Individual KYC form") do |key, label, kind|
  bdc_form_type_update(key, bdc_form_type("Horizon Capital", "Individual"), label, "payout_field" => kind)
end

When("{string} sets the max length of {string} to {int} in Form Types › Edit of the Individual KYC form") do |key, label, length|
  bdc_form_type_update(key, bdc_form_type("Horizon Capital", "Individual"), label, "vr_max_length" => length.to_s)
  expect(@bdc_last_flash.values.join(" ")).to include("Form type was successfully updated")
end

Then("the Form Types save is refused with {string}") do |text|
  expect(@bdc_last_status).to eq(422)
  expect(bdc_page_text).to include(text)
end

Given("{string} may edit Horizon Capital's form types") do |first|
  user = bdc_user(first)
  user.permissions.set(:enable_form_types)
  user.save!(validate: false)
end

When("{string} opens Form Custom Fields › Edit for {string}") do |key, label|
  bdc_request(key, :get, "/form_custom_fields/#{bdc_field('Horizon Capital', 'Individual', label).id}/edit")
end

Then("the custom field form has no payout field choice") do
  expect(@bdc_last_status).to eq(200)
  expect(bdc_page).to have_no_css("select[name='form_custom_field[payout_field]']", visible: :all)
end

When("{string} sends the payout field {string} for {string} through Form Custom Fields › Edit") do |key, kind, label|
  field = bdc_field("Horizon Capital", "Individual", label)
  bdc_request(key, :patch, "/form_custom_fields/#{field.id}", params: { form_custom_field: { label: field.label, payout_field: kind } })
end

When("{string} deletes the custom field {string} through Form Custom Fields") do |key, label|
  bdc_request(key, :delete, "/form_custom_fields/#{bdc_field('Horizon Capital', 'Individual', label).id}")
end

# ── The rollout rake task (support, per environment) ──

def bdc_run_proposal(firm_name, execute:)
  Rails.application.load_tasks unless Rake::Task.task_defined?("bank_detail_changes:propose_payout_fields")
  task = Rake::Task["bank_detail_changes:propose_payout_fields"]
  task.reenable
  env = { "FIRM_ID" => bdc_firm(firm_name).id.to_s, "EXECUTE" => execute ? "1" : nil }
  previous = env.keys.index_with { |k| ENV.fetch(k, nil) }
  env.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  @bdc_rake_output = StringIO.new
  original = $stdout
  $stdout = @bdc_rake_output
  task.invoke
ensure
  $stdout = original if original
  previous&.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
end

When("CapHive support runs the payout field proposal for {string}") do |firm_name|
  bdc_firm(firm_name)
  bdc_kyc("Farah Ali")
  bdc_kyc("Gulf Ventures LLC")
  bdc_run_proposal(firm_name, execute: false)
end

When("CapHive support runs the payout field proposal for {string} with EXECUTE=1") do |firm_name|
  bdc_kyc("Farah Ali")
  bdc_kyc("Gulf Ventures LLC")
  bdc_run_proposal(firm_name, execute: true)
end

Then("the proposal lists {string} on the {string} form as {string} with {int} filled value(s)") do |label, form, kind, count|
  line = @bdc_rake_output.string.lines.find { |l| l.include?(form) && l.include?(label) }
  expect(line).to be_present, @bdc_rake_output.string
  expect(line).to include("→ #{kind}")
  expect(line).to include("#{count} filled")
end

Then("the proposal does not list {string}") do |label|
  expect(@bdc_rake_output.string).not_to include(label)
end

Then("the proposal says {string}") do |text|
  expect(@bdc_rake_output.string).to include(text)
end
