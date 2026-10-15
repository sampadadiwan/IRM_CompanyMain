# Steps for: features/core/notification_investor_access_resolution.feature
#
# One contact, two folios (investors) in the same fund, one InvestorAccess on each. Accesses are
# named by a short label ("a", "b", "s") so scenarios can flip their switches; investors by name.
# Notifications are built directly (Noticed event + Notification) and the channel gates called on
# them - see the header of investor_kyc_notification_delivery_steps.rb for why a real send can't
# exercise email_enabled in the test env.

# Creates the investor (its own Investor-type entity) plus a commitment on @fund, so documents can
# be owned by either. Reused when the folio already exists.
def folio_gate_investor(name)
  @folio_investors ||= {}
  @folio_investors[name] ||= begin
    investor_entity = FactoryBot.create(:entity, entity_type: "Investor", name: "#{name} #{SecureRandom.hex(3)}")
    investor = FactoryBot.create(:investor, investor_entity_id: investor_entity.id, entity_id: @entity.id,
                                            investor_name: investor_entity.name)
    @folio_commitments ||= {}
    @folio_commitments[name] = FactoryBot.create(:capital_commitment, fund: @fund, investor:, entity: @fund.entity)
    investor
  end
end

# Grants `user` an approved access on the folio, in creation order (so ids follow step order).
def folio_gate_grant(label, user, folio_name)
  investor = folio_gate_investor(folio_name)
  @folio_accesses ||= {}
  @folio_accesses[label] = InvestorAccess.create!(investor:, user:, entity_id: @entity.id,
                                                  first_name: user.first_name, last_name: user.last_name,
                                                  email: user.email, approved: true)
end

# The contact holds the investor_advisor role, as user 2564 does in prod: InvestorAccess#ensure_entity_id
# only lets a user hold accesses on folios outside their own entity when they are an advisor.
def folio_gate_contact(email)
  user = User.find_by(email:) || FactoryBot.create(:user, email:, entity: folio_gate_investor("Folio A").investor_entity)
  user.add_role(:investor_advisor)
  user
end

Given('the contact {string} holds access {string} on folio {string} and access {string} on folio {string}') do |email, label_a, folio_a, label_b, folio_b|
  @contact = folio_gate_contact(email)
  # Order matters: label_a is created first, so it has the lower id the old `.first` picked.
  folio_gate_grant(label_a, @contact, folio_a)
  folio_gate_grant(label_b, @contact, folio_b)
  expect(@folio_accesses[label_a].id).to be < @folio_accesses[label_b].id
end

Given('the contact {string} holds access {string} on folio {string}') do |email, label, folio|
  user = User.find_by(email:) || FactoryBot.create(:user, email:, entity: folio_gate_investor(folio).investor_entity)
  folio_gate_grant(label, user, folio)
end

Given('access {string} has email {string}') do |label, state|
  @folio_accesses.fetch(label).update!(email_enabled: state == "on")
end

Given('access {string} has whatsapp {string}') do |label, state|
  @folio_accesses.fetch(label).update!(whatsapp_enabled: state == "on")
end

Given('there is a folio {string} in the fund without the contact') do |name|
  folio_gate_investor(name)
end

Given('the fund entity has WhatsApp enabled and the contact can receive WhatsApp') do
  @contact.update!(whatsapp_enabled: true, phone: "9876543210", call_code: "91")
  @entity.permissions.set(:enable_whatsapp)
  @entity.save!
end

# Document owners: a folio's commitment (the common statement/CAS case), the fund (no folio),
# or the folio's Investor record itself.
def folio_gate_document(owner)
  @doc_record = Document.create!(name: "Folio gate doc #{SecureRandom.hex(3)}", text: "x", entity: @entity,
                                 owner:, folder: owner.document_folder, user: @user,
                                 file: File.new("public/img/whatsappQR.png", "r"))
end

Given('there is a document owned by the commitment of folio {string}') do |name|
  folio_gate_investor(name)
  folio_gate_document(@folio_commitments.fetch(name))
end

Given('there is a document owned by the fund') do
  folio_gate_document(@fund)
end

Given('there is a document owned by the investor of folio {string}') do |name|
  folio_gate_document(folio_gate_investor(name))
end

# Mirrors DocumentSender.send: investor_id is the folio the sender fanned out for (or absent).
def folio_gate_build_document_notification(recipient, investor_id)
  params = { record: @doc_record, entity_id: @doc_record.entity_id, email_method: "send_document", msg: nil }
  params[:investor_id] = investor_id if investor_id
  event = DocumentNotifier.with(**params)
  event.save!
  @built_notification = DocumentNotifier::Notification.create!(event:, recipient:)
end

When('I build a document notification for the contact naming folio {string}') do |name|
  folio_gate_build_document_notification(@contact, folio_gate_investor(name).id)
end

When('I build a document notification for the contact without a folio') do
  folio_gate_build_document_notification(@contact, nil)
end

When('I build a document notification for {string} without a folio') do |email|
  folio_gate_build_document_notification(User.find_by!(email:), nil)
end

When('I build a document notification for the contact naming a missing investor') do
  folio_gate_build_document_notification(@contact, Investor.maximum(:id).to_i + 10_000)
end

When('I build a commitment notification for the contact on folio {string}') do |name|
  folio_gate_investor(name)
  commitment = @folio_commitments.fetch(name)
  event = FundCommitmentNotifier.with(record: commitment, entity_id: commitment.entity_id,
                                      email_method: "notify_commitment", custom_notification_id: nil)
  event.save!
  @built_notification = FundCommitmentNotifier::Notification.create!(event:, recipient: @contact)
end

Then('whatsapp_enabled should be false for the notification') do
  expect(@built_notification.whatsapp_enabled).to be_falsey
end

# Runs DeliveryMethods::WhatsApp#deliver the way whats_app_delivery.rb does, with the WATI call
# stubbed, and asserts it decides not to send.
Then('the WhatsApp delivery check should be false for the notification') do
  calls = []
  allow_any_instance_of(WhatsappGeneralNotification).to receive(:perform) { |*args| calls << args }
  delivery = DeliveryMethods::WhatsApp.new
  delivery.instance_variable_set(:@notification, @built_notification)
  delivery.instance_variable_set(:@event, @built_notification.event)
  delivery.deliver
  expect(calls).to be_empty
end

# Re-evaluates the gate with Rails.logger swapped for an in-memory one, then checks the line.
Then('the email gate log should name folio {string} and access {string}') do |name, label|
  io = StringIO.new
  original = Rails.logger
  Rails.logger = ActiveSupport::Logger.new(io)
  begin
    @built_notification.email_enabled
  ensure
    Rails.logger = original
  end
  line = io.string.lines.find { |l| l.include?("email_enabled false") }
  expect(line).to be_present
  expect(line).to include("notification #{@built_notification.id}")
  expect(line).to include("investor #{folio_gate_investor(name).id}")
  expect(line).to include("access #{@folio_accesses.fetch(label).id}")
end
