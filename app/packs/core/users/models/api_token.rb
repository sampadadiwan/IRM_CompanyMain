# A user's named integration token (Profile › API tokens): a row over one devise-api token, the
# same kind the website's .json endpoints already accept, so a script calls the API exactly as its
# user. Made only from a signed-in website session — which has already passed two-factor — so a
# two-factor user can automate without a code per call.
#
# Lives 90 days and is never refreshed (Users::TokensController refuses it); revoke stops it at once.
# Same shape as MobileDevice, which wraps a phone's token.
#
# openspec/changes/funds-json-api-hardening — design card ①. Worked examples H10–H12, E9–E11, X16–X21.
class ApiToken < ApplicationRecord
  MAX_LIVE = 10
  LIFETIME = 90.days
  # last_used_at is only rewritten when older than this, so every API call is not a write (E11)
  TOUCH_INTERVAL = 5.minutes

  belongs_to :user
  belongs_to :devise_api_token, class_name: "Devise::Api::Token"

  validates :name, presence: true, length: { maximum: 100 }
  validate :live_limit, on: :create

  # Not revoked and not past its lifetime
  scope :live, -> { where(revoked_at: nil).where(created_at: LIFETIME.ago..) }

  class << self
    # H10: the token row and its devise-api token together. Returns [api_token, access_token_string];
    # the string is shown once, in the create response, and stored nowhere else in the UI.
    def mint!(user:, name:)
      ActiveRecord::Base.connected_to(role: :writing) do
        transaction do
          # Serialises concurrent creates by the same user so the live limit holds (X18)
          user.lock!
          token = Devise::Api::Token.create!(resource_owner: user,
                                             access_token: Devise::Api::Token.generate_uniq_access_token(user),
                                             # devise-api requires one; it is never accepted (X21)
                                             refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user),
                                             expires_in: LIFETIME.to_i)
          [create!(user:, name:, devise_api_token: token), token.access_token]
        end
      end
    end
  end

  def live?
    revoked_at.nil? && created_at >= LIFETIME.ago
  end

  def expires_at
    created_at + LIFETIME
  end

  # H12: revokes the row and its devise-api token, so the next request with it answers 401
  def revoke!
    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        devise_api_token.update!(revoked_at: Time.current) if devise_api_token.revoked_at.nil?
        update!(revoked_at: Time.current) if revoked_at.nil?
      end
    end
    true
  end

  # E11: at most one write per TOUCH_INTERVAL
  def touch_last_used!
    return if last_used_at.present? && last_used_at > TOUCH_INTERVAL.ago

    ActiveRecord::Base.connected_to(role: :writing) { update_column(:last_used_at, Time.current) }
  end

  private

  # E10 X18: the 10th live token is allowed, the 11th refused
  def live_limit
    return if user.nil? || ApiToken.live.where(user_id: user.id).count < MAX_LIVE

    errors.add(:base, "You already have #{MAX_LIVE} live tokens — revoke one first")
  end
end
