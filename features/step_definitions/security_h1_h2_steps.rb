# Steps for the 2026-10 security review findings H1 (bulk document approval authorized, folder
# branch scoped to the firm) and H2 (SendGrid inbound webhook token, owner classes, author
# credit, deal-ingest headers). Design and worked examples: docs/security/security_review_2026_10.md
# (cards "H1 — Bulk document approval" and "H2 — SendGrid inbound email").
#
# H1 requests go through the rack_test driver as the signed-in user, the way the page or a crafted
# form would. H2 posts go through post_to_sendgrid (incoming_emails.rb), the way SendGrid does, with
# the webhook credential stubbed by SendgridInboundTestToken (features/support). @user / @entity come
# from the shared "there is a user ... for an entity" steps; "I am denied access"
# (tenant_isolation_batch1_steps.rb) checks for the Access Denied flash.

module SecurityH1H2Helpers
  H1_SAMPLE_PDF = "public/sample_uploads/sample_kyc1.pdf".freeze
  H2_ATTACHMENT = "public/sample_uploads/investors.xlsx".freeze

  # H1: a generated document awaiting approval, created now - inside the page's default
  # "yesterday to today" range. Its folder (or its owner's folder) decides its firm.
  def h1_generated_document(name:, folder: nil, owner: nil)
    Document.create!(entity_id: (folder || owner).entity_id, folder:, owner:, name:, owner_tag: "Generated",
                     file: File.open(H1_SAMPLE_PDF, "rb"), user_id: @user.id, approved: false)
  end

  # H1: a fresh session signed in as `user`, so a scenario can act as a second person
  def h1_sign_in(user)
    Capybara.reset_sessions!
    log_in(user)
  end

  # H1: the date range the page posts by default, as ISO dates (what its hidden date inputs send)
  def h1_date_range
    { start_date: Time.zone.yesterday.iso8601, end_date: Time.zone.today.iso8601 }
  end

  # H1: records which documents the approval job asked to notify their owners about. Approving with
  # notification calls Document#send_notification_for_owner for every document approved, so an empty
  # list means nothing was emailed.
  def h1_record_owner_notifications
    notified = h1_notified_documents
    allow_any_instance_of(Document).to receive(:send_notification_for_owner) { |document| notified << document.id }
  end

  def h1_notified_documents
    @h1_notified_documents ||= []
  end

  # H1-2..4: an employee of another fund firm holding the approver role
  def h1_other_firm_approver(name)
    @h1_other_entity = FactoryBot.create(:entity, name:, entity_type: "Investment Fund")
    @h1_other_user = FactoryBot.create(:user, entity: @h1_other_entity)
    @h1_other_user.add_role(:approver)
    @h1_other_user
  end

  # H1-H2 / H2: a KYC of the firm's investor (from "there is an existing investor ... with ... users")
  def h2_kyc
    @h2_kyc ||= FactoryBot.create(:investor_kyc, entity: @entity, investor: @investor, kyc_type: "individual", verified: false)
  end

  # H2: the users the feature names as senders
  def h2_sender(name)
    case name
    when "my firm's staff" then @user
    when "the investor's contact" then @investor_user
    when "a user of another firm"
      @h2_outsider ||= FactoryBot.create(:user, entity: FactoryBot.create(:entity, name: "Zeta Capital", entity_type: "Investment Fund"))
    when "support" then User.support_users.first
    else raise ArgumentError, "unknown sender #{name}"
    end
  end

  # H2: post_to_sendgrid options for each way the feature authenticates
  def h2_auth(auth)
    case auth
    when "no token" then { token: nil }
    when "a wrong token" then { token: "not-the-sendgrid-token" }
    when "the token" then { token: SendgridInboundTestToken::TOKEN }
    when "the previous token" then { token: SendgridInboundTestToken::PREVIOUS_TOKEN }
    when "the token as the Basic auth password" then { token: nil, basic_password: SendgridInboundTestToken::TOKEN }
    else raise ArgumentError, "unknown auth #{auth}"
    end
  end

  # H2: posts like SendGrid, keeping the response; logger warnings are spied on for H2-R
  def h2_post(to:, from:, auth: "the token", attachment: true, headers: true)
    allow(Rails.logger).to receive(:warn).and_call_original
    attachments = attachment ? { "attachment1" => Rack::Test::UploadedFile.new(H2_ATTACHMENT, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet") } : {}
    @h2_session = post_to_sendgrid(to:, from:, subject: "Signed KYC form", body: "Please find the form attached",
                                   attachments:, headers:, **h2_auth(auth))
  end
end
World(SecurityH1H2Helpers)

# Enforcement is an ENV flag: a scenario that set it puts back what the run started with
After("@sendgrid_inbound") do
  next unless @h2_enforce_set

  if @h2_enforce_was.nil?
    ENV.delete("SENDGRID_INBOUND_ENFORCE")
  else
    ENV["SENDGRID_INBOUND_ENFORCE"] = @h2_enforce_was
  end
end

# ---- H1 ---------------------------------------------------------------------------------------

Given('my firm has a folder {string} with {int} generated documents awaiting approval') do |name, count|
  # A folder of the firm, under its root folder like any other
  @h1_folder = Folder.create!(name:, entity: @entity, parent: @entity.root_folder)
  @h1_documents = Array.new(count) { |i| h1_generated_document(name: "#{name} notice #{i + 1}", folder: @h1_folder) }
end

Given('the investor has a KYC with a generated document awaiting approval') do
  # A generated KYC form, filed in the KYC's own folder through its owner
  @h1_kyc_document = h1_generated_document(name: "KYC Form", owner: h2_kyc)
end

Given('I am signed in as a document approver of another firm {string}') do |name|
  h1_sign_in(h1_other_firm_approver(name))
end

Given('there is an approver of another firm {string}') do |name|
  h1_other_firm_approver(name)
end

Given('I am signed in as a support user of my firm') do
  # Support, without the approver role
  support_user = FactoryBot.create(:user, entity: @entity, first_name: "Support")
  support_user.add_role(:support)
  h1_sign_in(support_user)
end

Given("I am signed in as the investor's user holding the approver role") do
  # An LP user (curr_role investor) - the role alone must not open the page
  @investor_user.add_role(:approver)
  h1_sign_in(@investor_user)
end

When("I bulk approve the firm's generated documents from yesterday to today with notification") do
  h1_record_owner_notifications
  page.driver.submit :post, approve_documents_path, h1_date_range.merge(notification: "1")
end

When("I bulk approve the firm's generated {string} documents from yesterday to today") do |owner_type|
  h1_record_owner_notifications
  page.driver.submit :post, approve_documents_path, h1_date_range.merge(owner_type:)
end

When('I bulk approve the documents of the folder from yesterday to today with notification') do
  h1_record_owner_notifications
  page.driver.submit :post, approve_documents_path, h1_date_range.merge(parent_folder_id: @h1_folder.id, notification: "1")
end

When('I open the approval page for the folder') do
  visit approve_documents_path(parent_folder_id: @h1_folder.id)
end

When('I open the approval page') do
  visit approve_documents_path
end

When('I open the Approve KYC Docs page') do
  # The URL the "Approve KYC Docs" item on the KYC list links to
  visit approve_documents_path(entity_id: @entity.id, owner_type: "InvestorKyc")
  expect(page).to have_text("Approve Generated Documents")
end

When('the document approval job runs for {string} with the folder and notification') do |name|
  h1_record_owner_notifications
  # Any caller of the job (not only the controller) names the firm and the folder separately
  DocumentApprovalJob.perform_now(Entity.find_by!(name:).id, *h1_date_range.values,
                                  { user_id: @h1_other_user.id, notification: "1", parent_folder_id: @h1_folder.id })
end

Then("the folder's generated documents are still unapproved") do
  expect(Document.where(id: @h1_documents.map(&:id), approved: true)).not_to exist
end

Then('no document owner was notified') do
  expect(h1_notified_documents).to be_empty
end

Then("the folder's name is not on the page") do
  expect(page).to have_no_text(@h1_folder.name)
end

Then("the call's notices are approved by me") do
  notices = Document.where(owner: @capital_call.capital_remittances, owner_tag: "Generated")
  expect(notices).to exist
  expect(notices.where(approved: false)).not_to exist
  expect(notices.unscope(:order).distinct.pluck(:approved_by_id)).to eq([@user.id])
end

Then("the KYC's generated document is approved by me") do
  @h1_kyc_document.reload
  expect(@h1_kyc_document.approved).to be(true)
  expect(@h1_kyc_document.approved_by_id).to eq(@user.id)
end

Then('I see the approval form') do
  expect(page).to have_text("Approve Generated Documents")
  expect(page).to have_button("Approve All")
end

# ---- H2 ---------------------------------------------------------------------------------------

Given('the investor has a KYC') do
  h2_kyc
end

Given('SendGrid inbound enforcement is on') do
  # Remember the run's own value for the After hook
  @h2_enforce_was = ENV.fetch("SENDGRID_INBOUND_ENFORCE", nil)
  @h2_enforce_set = true
  ENV["SENDGRID_INBOUND_ENFORCE"] = "1"
end

Given('SendGrid inbound enforcement is off') do
  @h2_enforce_was = ENV.fetch("SENDGRID_INBOUND_ENFORCE", nil)
  @h2_enforce_set = true
  ENV.delete("SENDGRID_INBOUND_ENFORCE")
end

Given('my firm has a deal {string} with an ingest address') do |name|
  # The deal, its ingest address, and the firm's admin (@user) as the sender with access to it
  @deal = FactoryBot.create(:deal, entity: @entity, name:)
  @ingest_address = @deal.ensure_deal_ingest_address || DealIngestAddress.create!(deal: @deal, address: @deal.id.to_s)
  AccessRight.create!(owner: @deal, user: @user, entity: @entity, access_type: "Deal")
end

Given('deal ingest requires email auth headers, as in production') do
  # Rails.env.production? itself is not stubbed - that would change far more than this check
  allow_any_instance_of(DealIngestAuthenticator).to receive(:email_auth_headers_required?).and_return(true)
end

When("SendGrid posts an email with an attachment from {string} to the KYC's address, sending {string}") do |sender, auth|
  h2_post(to: h2_kyc.incoming_email_address, from: h2_sender(sender).email, auth:)
end

When('SendGrid posts an email to an address naming the class {string}, sending the token') do |class_name|
  # Same shape as an owner address, naming a class that does not take incoming email
  h2_post(to: "#{class_name}.#{@user.id}@#{ENV.fetch('INCOMING_EMAIL_DOMAIN')}", from: @user.email)
end

When("SendGrid posts an email from my firm's staff to the deal's ingest address, sending the token") do
  h2_post(to: @ingest_address.full_address, from: @user.email, attachment: false)
end

When("SendGrid posts an email without headers from my firm's staff to the deal's ingest address, sending the token") do
  h2_post(to: @ingest_address.full_address, from: @user.email, attachment: false, headers: false)
end

Then('the webhook answers {int}') do |status|
  expect(@h2_session.last_response.status).to eq(status)
end

Then('nothing is filed') do
  expect(IncomingEmail.count).to eq(0)
  expect(Document.where(owner_type: "IncomingEmail")).not_to exist
end

Then('no incoming email is filed') do
  expect(IncomingEmail.count).to eq(0)
end

Then('the email is filed against the KYC with {int} document credited to {string}') do |count, sender|
  incoming = IncomingEmail.last
  # The KYC reloads as its STI subclass (IndividualKyc) while h2_kyc is the InvestorKyc the factory
  # built, and AR == compares classes, so match on the polymorphic key instead
  expect([incoming.owner_type, incoming.owner_id]).to eq([h2_kyc.class.base_class.name, h2_kyc.id])
  expect(incoming.entity_id).to eq(@entity.id)
  expect(incoming.documents.count).to eq(count)
  expect(incoming.documents.unscope(:order).distinct.pluck(:user_id)).to eq([h2_sender(sender).id])
end

Then('an unauthenticated SendGrid post was logged') do
  expect(Rails.logger).to have_received(:warn).with(a_string_including("[SendgridInbound] unauthenticated"))
end
