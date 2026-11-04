# H2 (2026-10 security review): IncomingEmailsController#sendgrid checks a webhook token against
# credentials[:sendgrid_inbound][:tokens] and refuses posts without it once
# SENDGRID_INBOUND_ENFORCE=1. Tests never touch the credential files: every step that posts to the
# webhook stubs that credential with these test tokens and sends TOKEN, so the existing SendGrid
# features stay green with enforcement on. PREVIOUS_TOKEN stands for a token being rotated out (H2-7).
# Design: docs/security/security_review_2026_10.md#h2--sendgrid-inbound-email
module SendgridInboundTestToken
  TOKEN = "test-sendgrid-inbound-token".freeze
  PREVIOUS_TOKEN = "test-sendgrid-inbound-token-previous".freeze

  # Makes this test run's credentials list the given webhook tokens. Every other credential is read
  # as normal. RSpec mocks reset after each scenario.
  def stub_sendgrid_inbound_tokens(tokens = [TOKEN, PREVIOUS_TOKEN])
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:sendgrid_inbound, :tokens).and_return(tokens)
  end

  # Attachments from a sender the owner's firm does not know are credited to the support user
  # (IncomingEmail#save_attachments, H2-6). Production always has one; a test database may not, so
  # steps that post attachments make sure one exists - in a firm of its own, so it is nobody's staff.
  def ensure_sendgrid_fallback_author
    User.support_users.first || begin
      support_entity = FactoryBot.create(:entity, name: "CapHive Support #{SecureRandom.hex(3)}", entity_type: "Company")
      FactoryBot.create(:user, entity: support_entity, first_name: "Support").tap { |user| user.add_role(:support) }
    end
  end
end
World(SendgridInboundTestToken)
