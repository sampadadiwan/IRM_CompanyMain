# A company's own Zoho Sign account (design card ①). Documents sent at or after connected_at use it;
# earlier ones finish on CapHive's platform account (ZohoSignAccount.for_document). One per company,
# reached only through the company in the URL or the webhook token - never by id from a param.
class ZohoSignConnection < ApplicationRecord
  extend Enumerize

  audited except: %i[client_secret refresh_token webhook_secret]

  belongs_to :entity
  belongs_to :connected_by, class_name: "User", optional: true

  encrypts :client_secret, :refresh_token, :webhook_secret
  has_secure_token :webhook_token, length: 32

  enumerize :status, in: %i[connected needs_reauth], default: :connected, predicates: true

  validates :region, inclusion: { in: ZohoSignClient::REGIONS.keys, message: "Pick a Zoho region" }
  validates :client_id, presence: true, length: { maximum: 100 }
  validates :client_secret, :refresh_token, :webhook_secret, :connected_at, presence: true
  validates :last_error, length: { maximum: 255 }

  normalizes :client_id, with: ->(value) { value.strip }

  before_validation :set_defaults, on: :create

  def self.new_webhook_secret
    SecureRandom.base58(40)
  end

  def account
    ZohoSignAccount.new(region:, client_id:, client_secret:, refresh_token:, webhook_secret:, connection: self)
  end

  def region_name
    ZohoSignClient::REGIONS[region]&.name
  end

  # X8, X11: Zoho refused the stored credentials. Only the call whose conditional update moved the
  # connection out of Connected notifies, so many failing calls send one email. Returns that flag.
  def mark_needs_reauth!(reason)
    transitioned = self.class.where(id:, status: "connected")
                       .update_all(status: "needs_reauth", last_error: reason.to_s.truncate(255), updated_at: Time.current) == 1
    reload
    ZohoSignConnectionNotifier.with(record: self, entity_id:).deliver(entity.employees.active.company_admins) if transitioned
    transitioned
  end

  def mark_connected!
    update!(status: :connected, last_error: nil)
  end

  # X6: documents still out for signature on this account - the ones disconnecting would strand.
  def documents_out_for_signature
    Document.where(entity_id:, sent_for_esign: true, sent_for_esign_date: connected_at..)
            .where(esign_status: Document::ESIGN_ACTIVE_STATUSES)
  end

  # H3: the secret can be shown once; afterwards it can only be replaced. Returns nil once revealed.
  def reveal_webhook_secret!
    revealed = self.class.where(id:, webhook_secret_revealed_at: nil).update_all(webhook_secret_revealed_at: Time.current) == 1
    reload
    webhook_secret if revealed
  end

  # E7: updates signed with the old secret are refused from now on. The new one is shown once, now.
  def regenerate_webhook_secret!
    update!(webhook_secret: self.class.new_webhook_secret, webhook_secret_revealed_at: Time.current)
    webhook_secret
  end

  private

  def set_defaults
    self.connected_at ||= Time.current
    self.webhook_secret ||= self.class.new_webhook_secret
  end
end
