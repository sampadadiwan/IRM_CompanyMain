# Steps for the "custom notification whatsapp field" send/skip behavior, split across two
# concerns:
#   1. NotificationExtensions#custom_notification_whatsapp_present? - the gate the :whats_app
#      deliver_by's config.if actually checks in production, deciding whether the delivery job
#      is enqueued at all. Testable directly against a real Notification, no bypass needed.
#   2. DeliveryMethods::WhatsApp#deliver - what happens once that job is allowed to run. Whats_App
#      is forced off in the test env (see BaseNotifier) to avoid ever hitting the real WATI API
#      through Noticed's normal dispatch, so this is invoked directly rather than through a job.

Given('the investor user has WhatsApp enabled') do
  @investor_user.update!(whatsapp_enabled: true, phone: "1234567890", call_code: "91")
  @investor_access.update!(whatsapp_enabled: true)
  @entity.permissions.set(:enable_whatsapp)
  @entity.save!
end

Given('the document notifies the WhatsApp-enabled investor user') do
  @document = Document.last
  allow_any_instance_of(Document).to receive(:notification_users).and_return([@investor_user])
end

Given('there is a custom notification for the document with subject {string} and whatsapp {string}') do |subject, whatsapp_message|
  @custom_notification = CustomNotification.create!(
    entity: @entity,
    owner: @entity,
    for_type: "Send Document",
    email_method: "send_document",
    subject: subject,
    body: Faker::Lorem.paragraph,
    whatsapp: whatsapp_message,
    enabled: true
  )
end

Given('there is a custom notification for the document with subject {string} and a blank whatsapp field') do |subject|
  @custom_notification = CustomNotification.create!(
    entity: @entity,
    owner: @entity,
    for_type: "Send Document",
    email_method: "send_document",
    subject: subject,
    body: Faker::Lorem.paragraph,
    # Saved as an empty string, matching what the form's text_area submits when left blank -
    # this is distinct from nil and is the exact case the fallback bug hid behind.
    whatsapp: "",
    enabled: true
  )
end

When('the document is sent to the investor') do
  DocumentSender.send(@document, @investor_user.id, @custom_notification.id)
  @notification = Noticed::Notification.where(type: "DocumentNotifier::Notification", recipient_id: @investor_user.id).last
end

When('the document\'s WhatsApp delivery is attempted') do
  @whatsapp_calls = []
  allow_any_instance_of(WhatsappGeneralNotification).to receive(:perform) do |_instance, entity_name, message, *_rest|
    @whatsapp_calls << { entity_name:, message: }
  end

  delivery = DeliveryMethods::WhatsApp.new
  delivery.instance_variable_set(:@notification, @notification)
  delivery.instance_variable_set(:@event, @notification.event)
  delivery.deliver
end

Then('a WhatsApp message {string} is sent to the investor') do |message|
  expect(@whatsapp_calls.size).to eq(1)
  expect(@whatsapp_calls.first[:message]).to eq(message)
end

# Proves the same method the :whats_app deliver_by's config.if checks in production would block
# this notification, so the delivery job is never enqueued at all - not just short-circuited
# once it's already running.
Then('the notifier does not enqueue a WhatsApp delivery for the investor') do
  expect(@notification.custom_notification_whatsapp_present?).to be(false)
end
