# Stub the WhatsApp job so feature tests don't hit the real WATI API.
# Tag a scenario/feature with @stub-whatsapp to activate.
Before('@stub-whatsapp') do
  allow(SendOtpToWhatsappJob).to receive(:perform_later)
end
