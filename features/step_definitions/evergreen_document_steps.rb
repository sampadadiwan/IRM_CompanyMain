# Steps for features/fund/evergreen/dealing_documents.feature (and E51 in documents.feature):
# contract notes and redemption advices generated from the fund's (or folio's) Word templates on a
# dealing date — Generate documents → Approve & send — and the email-only path without templates.
# Worked examples H57–H62, E66–E70, X26–X30 — openspec/changes/open-ended-funds/design.md#worked-examples

# ---- Helpers ----

EVERGREEN_DOC_SUBJECTS = { "contract note" => "Contract note", "redemption advice" => "Redemption advice" }.freeze

# The investor email subject for a document kind ("contract note" / "redemption advice")
def evergreen_doc_subject(kind)
  "#{@fund.name}: #{EVERGREEN_DOC_SUBJECTS.fetch(kind)}"
end

# A team member by first name: Asha (the logged-in GP user), Ravi (the approver), …
def evergreen_doc_user(name)
  User.where(entity_id: @fund.entity_id, first_name: name).order(:id).last || raise("No user called #{name}")
end

# Investor emails of one kind delivered to an investor's portal user
def evergreen_doc_mails(investor_name, kind)
  user = @investor_users.fetch(investor_name)
  ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) && m.subject == evergreen_doc_subject(kind) }
end

def evergreen_doc_body(mail)
  part = mail.html_part || mail.text_part || mail
  # HTML bodies escape "&" (Approve &amp; send); compare against the text the reader sees
  CGI.unescapeHTML(part.body.decoded.dup.force_encoding("UTF-8"))
end

# Settled fills of a dealing date (units allotted / cancelled) — the ones a document is for
def evergreen_doc_settled_fills(date)
  evergreen_dealing_date(date).dealing_fills.where.not(fund_unit_id: nil).order(:id)
end

# The job's "N documents generated…" message goes to the user who clicked as a UserAlert broadcast
# (never saved), so capture each broadcast message. The stub is global, so it also sees a job that
# runs inline on the app server's thread.
def evergreen_capture_job_alerts
  @evergreen_job_alerts = []
  alerts = @evergreen_job_alerts
  allow_any_instance_of(UserAlert).to receive(:broadcast) { |ua| alerts << ua.message.to_s }
end

# A signed-in HTTP session (no browser) to post a form the screen does not offer
def evergreen_doc_session(user)
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.post "/users/sign_in", params: { user: { email: user.email, password: "password" } }
  session
end

# Follow a direct request's redirect and keep where it went and what the page said
def evergreen_doc_follow(session)
  @direct_location = session.response.location.to_s
  session.follow_redirect! while session.response.redirect?
  @direct_body = session.response.body.to_s
end

# A Word template on the fund or a folio (tag "Contract Note Template" / "Redemption Advice Template")
def evergreen_doc_template(owner, name, tag, file)
  Document.create!(entity_id: @fund.entity_id, owner:, name:, owner_tag: tag, template: true, user: @gp_user || @user,
                   file: Rails.public_path.join("sample_uploads", file).open("rb"))
end

# ---- Setup ----

# The fund's template of one kind (rendered from a sample Word template that fills with the context)
Given('the fund has the {string} {string}') do |tag, name|
  evergreen_doc_template(@fund, name, tag, "Commitment Agreement Template.docx")
end

# H60 / X30: a folio template with the fund template's name overrides it for that folio
Given('folio {string} has its own {string} {string} from the file {string}') do |folio, tag, name, file|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  evergreen_doc_template(cc, name, tag, file)
end

# The shared H21 dealing: A Ltd ₹3,00,00,000 and B LLP ₹2,50,00,000 redemptions over a 5 % FIFO gate,
# P Family Trust's ₹5,00,00,000 pre-funded subscription, 31 Oct NAV ₹10,220.00, confirmed on 2 Nov 2026
Given('the 2 Nov 2026 dealing date is confirmed with P Family Trust subscribing and A Ltd and B LLP redeeming') do
  steps %(
    Given today is "2026-09-10"
    And "A Ltd" has placed a "redemption" order "folio=F-012;amount=30000000" received "2026-09-10 09:00"
    And "B LLP" has placed a "redemption" order "folio=F-031;amount=25000000" received "2026-09-18 09:15"
    And today is "2026-10-20"
    And "P Family Trust" has placed a "subscription" order "amount=50000000" received "2026-10-20 09:00"
    And "P Family Trust" has paid the subscription on "2026-10-25"
    And an approved NAV for class "A" on "2026-10-31" with NAV per unit "10,220" and units "100000"
    And today is "2026-11-02"
    And the fund admin confirms dealing date "2026-11-02"
  )
end

# Mark a redemption paid through the tracker's service (the UI path is the H24 step)
Given('the redemption of {string} on {string} was marked paid on {string}') do |name, date, paid_on|
  steps %(Given today is "#{paid_on}")
  payment = evergreen_fill_of(name, date).capital_distribution_payment
  ok, error = EvergreenPayments.mark_redemption_paid(payment, payment_date: Date.parse(paid_on), reference: "UTR-#{name.parameterize}")
  raise "mark paid failed: #{error}" unless ok
end

# Generate documents as the background job does for the logged-in GP user (Asha)
Given('the documents of dealing date {string} were generated') do |date|
  evergreen_capture_job_alerts
  EvergreenDocumentsJob.perform_now(evergreen_dealing_date(date).id, @gp_user.id)
  expect(EvergreenDealingDocuments.to_generate(evergreen_dealing_date(date))).to be_empty
end

# Approve & send through the service, as the named approver
Given('{string} approved and sent the documents of dealing date {string}') do |name, date|
  sent = EvergreenDealingDocuments.approve_and_send(evergreen_dealing_date(date), evergreen_doc_user(name))
  expect(sent).to be_positive
end

When('{string} approves and sends the documents of dealing date {string}') do |name, date|
  steps %(Given "#{name}" approved and sent the documents of dealing date "#{date}")
end

Given('the fund has switched off the documents awaiting approval alert') do
  @fund.evergreen_fund_setting.update!(notifications: { "documents_awaiting_approval" => false })
end

Given('{string} is also an approver') do |name|
  evergreen_doc_user(name).add_role(:approver)
end

# ---- Screen actions ----

When('I click Generate documents on the dealing date {string}') do |date|
  evergreen_capture_job_alerts
  @documents_before = Document.where(owner_tag: "Generated").count
  evergreen_visit(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
  click_on("generate_documents")
  # Generate / Send emails confirm first with the Immediate Actions popup
  # (only in a browser — rack_test has no JS, the button posts straight away)
  within("#confirmModal") { click_on("Proceed") } unless Capybara.current_driver == :rack_test
  # In tests the job runs inline inside this request (LibreOffice per document), so the redirect
  # with its flash can take longer than Capybara's default wait — wait for it here
  expect(page).to have_content(/Generating|Nothing to generate|Emailed/, wait: 120)
end

When('I click Approve & send on the dealing date {string}') do |date|
  evergreen_visit(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
  click_on("approve_documents")
  expect(page).to have_css("#confirmModal", visible: true)
end

When('I proceed in the confirm popup') do
  within("#confirmModal") { click_on("Proceed") }
end

When('I click Regenerate on the document of {string} on {string}') do |name, date|
  # Note every fill's document first, to show the others are untouched
  @documents_by_fill = evergreen_dealing_date(date).dealing_fills.pluck(:id, :document_id).to_h
  @regenerated_fill = evergreen_fill_of(name, date)
  evergreen_visit(evergreen_dealing_date_path(@fund, @regenerated_fill.dealing_date))
  evergreen_show_fill_tab(@regenerated_fill)
  click_on("regenerate_#{@regenerated_fill.id}")
end

# H62: someone fixes a heading in the template (a new Word file uploaded on the same template)
When('the template {string} is corrected') do |name|
  template = Document.find_by!(entity_id: @fund.entity_id, owner: @fund, name:, template: true)
  template.file = File.open(Rails.public_path.join("sample_uploads/Commitment Agreement Template2.docx"), "rb")
  template.save!
  @corrected_template = template.reload
end

# X26 / X27 / X29: post the action directly, as a hand-made request would
When('{string} posts {string} for dealing date {string} directly') do |name, action, date|
  dd = evergreen_dealing_date(date)
  session = evergreen_doc_session(evergreen_doc_user(name))
  path = { "approve_documents" => approve_documents_evergreen_dealing_date_path(@fund, dd),
           "generate_documents" => generate_documents_evergreen_dealing_date_path(@fund, dd) }.fetch(action)
  session.post path
  evergreen_doc_follow(session)
end

When('{string} posts regenerate for the document of {string} on {string} directly') do |name, investor, date|
  fill = evergreen_fill_of(investor, date)
  @document_before = fill.document&.attributes
  session = evergreen_doc_session(evergreen_doc_user(name))
  session.post regenerate_evergreen_dealing_date_fill_path(@fund, fill.dealing_date, fill)
  evergreen_doc_follow(session)
end

# Refused by policy: Pundit's deny_access sends the user to the home page with "Access Denied"
Then('the direct request should be refused') do
  expect(@direct_location).not_to include("sign_in")
  expect(@direct_location).not_to include("/dealing_dates/")
  expect(@direct_body).to include("Access Denied")
end

# Refused by the action itself: back on the dealing date with the reason
Then('the direct request should be refused with {string}') do |text|
  expect(@direct_location).not_to include("sign_in")
  expect(CGI.unescapeHTML(@direct_body)).to include(text)
end

# ---- Assertions: documents ----

# | investor | folio | template | approved |
Then('the dealing date {string} should have these documents:') do |date, table|
  table.hashes.each do |row|
    fill = nil
    # Document conversion may finish on LibreOffice's own thread
    eventually(timeout: 20) do
      fill = evergreen_fill_of(row["investor"], date).reload
      expect(fill.document).to be_present, "no document for #{row['investor']}"
    end
    doc = fill.document
    expect(doc.owner).to eq(@fund.capital_commitments.find_by!(folio_id: row["folio"]))
    expect(doc.owner_tag).to eq("Generated")
    expect(doc.from_template&.name).to eq(row["template"]) if row["template"]
    expect(doc.from_template&.owner&.folio_id).to eq(row["template folio"]) if row["template folio"].present?
    expect(doc.from_template&.owner).to eq(@fund) if row["template folio"] == ""
    expect(doc.approved.to_s).to eq(row["approved"]) if row["approved"]
  end
end

Then('no new document should have been generated') do
  expect(Document.where(owner_tag: "Generated").count).to eq(@documents_before)
end

Then('{string} on {string} should have no document') do |name, date|
  expect(evergreen_fill_of(name, date).reload.document).to be_nil
end

Then('only {int} document(s) should have been generated on {string}') do |count, date|
  expect(evergreen_dealing_date(date).dealing_fills.where.not(document_id: nil).count).to eq(count)
end

Then('no document should be stored on folio {string}') do |folio|
  cc = @fund.capital_commitments.find_by!(folio_id: folio)
  expect(Document.where(owner: cc).not_template.count).to eq(0)
end

Then('the documents of dealing date {string} should be approved by {string}') do |date, name|
  approver = evergreen_doc_user(name)
  fills = evergreen_doc_settled_fills(date).where.not(document_id: nil).includes(:document)
  expect(fills).not_to be_empty
  fills.each do |f|
    expect(f.document.approved).to be(true)
    expect(f.document.approved_by_id).to eq(approver.id)
  end
end

Then('no document of dealing date {string} should be approved') do |date|
  docs = Document.where(id: evergreen_dealing_date(date).dealing_fills.where.not(document_id: nil).select(:document_id))
  expect(docs).not_to be_empty
  expect(docs.where(approved: true)).to be_empty
end

Then('every settled order of dealing date {string} should have its email sent') do |date|
  expect(evergreen_doc_settled_fills(date).where(document_sent_at: nil)).to be_empty
end

Then('the document of {string} on {string} should be replaced by a new unapproved one from {string}') do |name, date, template|
  old_id = @documents_by_fill.fetch(@regenerated_fill.id)
  fill = evergreen_fill_of(name, date).reload
  expect(Document.exists?(old_id)).to be(false), "the old document #{old_id} is still there"
  expect(fill.document_id).to be_present
  expect(fill.document_id).not_to eq(old_id)
  expect(fill.document.approved).to be(false)
  expect(fill.document.owner).to eq(fill.dealing_order.capital_commitment)
  expect(fill.document.from_template&.name).to eq(template)
  # Generated after the template was corrected
  expect(fill.document.created_at).to be >= @corrected_template.updated_at
end

Then('the other documents of {string} should be untouched') do |date|
  evergreen_dealing_date(date).dealing_fills.where.not(id: @regenerated_fill.id).find_each do |f|
    expect(f.document_id).to eq(@documents_by_fill[f.id])
  end
end

Then('the document of {string} on {string} should be unchanged') do |name, date|
  doc = evergreen_fill_of(name, date).reload.document
  expect(doc&.attributes&.except("updated_at")).to eq(@document_before&.except("updated_at"))
  expect(doc.approved).to be(true)
end

# ---- Assertions: emails ----

Then('no contract note or redemption advice email should have gone to investors') do
  subjects = ActionMailer::Base.deliveries.map(&:subject)
  expect(subjects).not_to include(evergreen_doc_subject("contract note"))
  expect(subjects).not_to include(evergreen_doc_subject("redemption advice"))
end

Then('{string} should have been sent {int} {string} email(s)') do |name, count, kind|
  expect(evergreen_doc_mails(name, kind).size).to eq(count)
end

Then('{string} should get the {string} email with the PDF attached') do |name, kind|
  mails = evergreen_doc_mails(name, kind)
  expect(mails.size).to eq(1), "#{name} got #{mails.size} #{kind} emails"
  names = mails.first.attachments.map(&:filename)
  expect(names.grep(/\.pdf\z/i)).not_to be_empty, "attachments: #{names.inspect}"
end

Then('{string} should get the {string} email without an attachment') do |name, kind|
  mails = evergreen_doc_mails(name, kind)
  expect(mails.size).to eq(1), "#{name} got #{mails.size} #{kind} emails"
  expect(mails.first.attachments).to be_empty
end

# E51: the figures are in the email body itself
Then('the {string} email to {string} should show:') do |kind, name, table|
  mail = evergreen_doc_mails(name, kind).last
  expect(mail).to be_present, "#{name} got no #{kind} email"
  body = evergreen_doc_body(mail)
  table.raw.flatten.each { |text| expect(body).to include(text) }
end

# ---- Assertions: alerts ----

# The job's own alert to the user who clicked Generate documents
Then('I should get the job alert {string}') do |text|
  expect(@evergreen_job_alerts.join("\n")).to include(text), "job alerts: #{@evergreen_job_alerts.inspect}"
end

Then('the job alert should also say {string}') do |text|
  expect(@evergreen_job_alerts.join("\n")).to include(text), "job alerts: #{@evergreen_job_alerts.inspect}"
end

Then('no job alert should have been sent') do
  expect(@evergreen_job_alerts).to be_empty
end

# The approvers' "Documents awaiting approval" alert, by email and in-app, once
Then('{string} should get one documents awaiting approval alert for {string} saying:') do |name, date, table|
  user = evergreen_doc_user(name)
  title = "#{@fund.name}: Documents awaiting approval for #{I18n.l(Date.parse(date), format: :email, locale: :en)}"
  mails = ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) && m.subject == title }
  expect(mails.size).to eq(1), "#{name} got #{ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) }.map(&:subject).inspect}"
  inapp = Noticed::Notification.where(recipient: user, type: "EvergreenOpsNotifier::Notification").map(&:message)
  expect(inapp.count(title)).to eq(1), "#{name} in-app: #{inapp.inspect}"
  body = evergreen_doc_body(mails.first)
  table.raw.flatten.each { |text| expect(body).to include(text) }
  expect(body).to include(evergreen_dealing_date_path(@fund, evergreen_dealing_date(date)))
end

Then('{string} should get no documents awaiting approval alert') do |name|
  user = evergreen_doc_user(name)
  expect(ActionMailer::Base.deliveries.select { |m| Array(m.to).include?(user.email) }.map(&:subject).grep(/Documents awaiting approval/)).to be_empty
  expect(Noticed::Notification.where(recipient: user, type: "EvergreenOpsNotifier::Notification").map(&:message).grep(/Documents awaiting approval/)).to be_empty
end

# ---- Assertions: the dealing-date screen ----

Then('the approve popup should say {string}') do |text|
  within("#confirmModal") { expect(page).to have_content(text) }
end

Then('the approve popup should not mention {string}') do |text|
  within("#confirmModal") { expect(page).not_to have_content(text) }
end

Then('the tracker row of {string} on {string} should read {string}') do |name, date, text|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(find("#fill_#{fill.id}")).to have_content(text)
end

Then('the tracker row of {string} on {string} should offer Regenerate') do |name, date|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(page).to have_css("#regenerate_#{fill.id}")
end

Then('the tracker row of {string} on {string} should not offer Regenerate') do |name, date|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  expect(page).to have_css("#fill_#{fill.id}")
  expect(page).not_to have_css("#regenerate_#{fill.id}")
end

Then('the dealing date actions should offer neither Generate documents nor Approve & send') do
  within("#dealing_date_actions") do
    expect(page).not_to have_css("#generate_documents")
    expect(page).not_to have_css("#approve_documents")
    expect(page).not_to have_css("#approve_documents_disabled")
  end
end

Then('the dealing date actions should not offer Approve & send') do
  expect(page).to have_css("#dealing_date_actions")
  expect(page).not_to have_css("#approve_documents")
end

Then('Close dealing date should be enabled') do
  expect(page).to have_css("#close_dealing")
end

Then('Close dealing date should be disabled with {string}') do |text|
  within("#dealing_date_actions") do
    expect(page).not_to have_css("#close_dealing")
    expect(page).to have_content("Close dealing date")
    expect(page).to have_content(text)
  end
end

# A not-applicable step names why in its tooltip ("Not applicable — Optional — no template")
Then('the step {string} should be not applicable with {string}') do |task, reason|
  within("#journey_step_bar") do
    pill = find(".journey-step[data-journey-status='na']", text: task)
    expect(pill["data-bs-title"].to_s).to include(reason)
  end
end

Then('the step {string} should apply') do |task|
  within("#journey_step_bar") do
    expect(page).to have_css(".journey-step", text: task)
    expect(page).not_to have_css(".journey-step[data-journey-status='na']", text: task)
  end
end

# ---- Assertions: the investor portal ----

Then('the investor tab {string} should not list the {string} of {string} on {string}') do |tab, kind, name, date|
  steps %(When I open the investor tab "#{tab}")
  doc = evergreen_fill_of(name, date).document
  within("#lp_#{tab.parameterize}") do
    expect(page).not_to have_content(doc.name) if doc
    expect(page).not_to have_link(EVERGREEN_DOC_SUBJECTS.fetch(kind))
  end
end

Then('the investor tab {string} should list the {string} of {string} on {string}') do |tab, kind, name, date|
  steps %(When I open the investor tab "#{tab}")
  doc = evergreen_fill_of(name, date).document
  within("#lp_#{tab.parameterize}") do
    if tab == "Transactions"
      expect(page).to have_link(EVERGREEN_DOC_SUBJECTS.fetch(kind), href: document_path(doc))
    else
      expect(page).to have_link(doc.name, href: document_path(doc))
    end
  end
end

# E224: Resend sits in the Actions column as an outline button with the "Immediate Actions" popup
Then('the Resend of {string} on {string} should be a button asking {string}') do |name, date, text|
  fill = evergreen_fill_of(name, date)
  evergreen_show_fill_tab(fill)
  button = find("#fill_#{fill.id} td.action-col #resend_#{fill.id}", visible: :all)
  expect(button[:class]).to include("btn-outline-primary")
  expect(button["data-action"]).to include("confirm#popup")
  expect(button["data-msg"]).to include("Immediate Actions").and include(text)
end

# E225: the order page's Dealing card — one row per dealing date, the same badges and buttons as the tracker
When('I open the {string} order of {string}') do |kind, name|
  evergreen_visit(evergreen_order_path(@fund, evergreen_order_of(name, kind)))
end

Then("the order's dealing row for {string} should read {string}") do |date, text|
  order = DealingOrder.find(current_path[%r{/orders/(\d+)}, 1])
  fill = order.dealing_fills.joins(:dealing_date).find_by!(dealing_dates: { date: Date.parse(date) })
  expect(find("#order_fills #fill_#{fill.id}")).to have_content(text)
end

Then("the order's units dealt should read {string}") do |text|
  expect(find("#order_units_dealt")).to have_content(text)
end

# E225 / E226: the order page's investor, folio and dealing date are links for fund users, plain text for LPs
def evergreen_order_page_links(order)
  [investor_path(order.investor), evergreen_folio_path(@fund, order.capital_commitment), evergreen_dealing_date_path(@fund, order.dealing_date)]
end

Then('the order page should link the investor, folio and dealing date') do
  order = DealingOrder.find(current_path[%r{/orders/(\d+)}, 1])
  within("#order_card") { evergreen_order_page_links(order).each { |href| expect(page).to have_css("a[href='#{href}']") } }
end

Then('the order page should not link the investor, folio or dealing date') do
  order = DealingOrder.find(current_path[%r{/orders/(\d+)}, 1])
  within("#order_card") { evergreen_order_page_links(order).each { |href| expect(page).to have_no_css("a[href='#{href}']") } }
  expect(page).to have_no_css("#order_dealing")
  # The LP's read-only dealing summary: no row actions and no links to fund-user records (an approved
  # document link is the only link allowed)
  if page.has_css?("#order_dealing_summary", wait: 0)
    within("#order_dealing_summary") do
      expect(page).to have_no_css(".action-col, button")
      expect(page).to have_no_css("a[href*='/capital_remittances/'], a[href*='/fund_units/'], a[href*='/evergreen/dealing/']")
    end
  end
end
