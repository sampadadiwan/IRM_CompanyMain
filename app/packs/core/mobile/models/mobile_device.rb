# One phone (one app install) a user has signed in on with the LP mobile app.
#
# The row binds together the phone's current devise-api token and its Expo push address, and it is
# the only place a phone session ends: revoking the row revokes the token and stops pushes in the
# same write, so "sign out a lost phone", "password changed" and "app reinstalled" can never leave
# half a session behind.
#
# Tokens are minted here, after the phone sign-in has cleared two-factor (MobileSignIn). Every
# /api/mobile/v1 request is authenticated through .authenticate, which only accepts a token that is
# the CURRENT token of a live device — so a devise-api token minted elsewhere (e.g. devise-api's
# own /users/tokens/sign_in, which never asks for a code) cannot reach the phone API (X7).
#
# openspec/changes/lp-mobile-app — design card ③.
class MobileDevice < ApplicationRecord
  PLATFORMS = %w[ios android].freeze
  PUSH_STATUSES = %w[none ok not_registered].freeze
  # A user may keep at most this many live phones; signing in on another evicts the least
  # recently used (E5).
  MAX_LIVE_DEVICES = 10
  # A phone unused for this long must sign in again (E8).
  SESSION_LIFETIME = 90.days
  # last_used_at is only rewritten when older than this, so every API call is not a write.
  TOUCH_INTERVAL = 5.minutes
  # Access tokens are short-lived; the device row, not the refresh token's own expiry, decides how
  # long a phone stays signed in.
  ACCESS_TOKEN_TTL = 1.hour

  belongs_to :user
  belongs_to :devise_api_token, class_name: "Devise::Api::Token", optional: true

  validates :install_id, presence: true, length: { maximum: 64 }
  validates :platform, inclusion: { in: PLATFORMS }
  validates :name, length: { maximum: 100 }
  validates :app_version, length: { maximum: 20 }
  validates :region_code, presence: true, length: { maximum: 10 }
  validates :push_token, length: { maximum: 255 }
  validates :push_status, inclusion: { in: PUSH_STATUSES }
  validates :revoked_reason, length: { maximum: 30 }

  # Not signed out and used within the session lifetime (E8)
  scope :live, -> { where(revoked_at: nil).where(last_used_at: SESSION_LIFETIME.ago..) }
  # Live phones that should receive a push (E26 push switched off, E27 revoked, X10 dead address)
  scope :pushable, -> { live.where(push_enabled: true, push_status: "ok").where.not(push_token: nil) }

  class << self
    # Registers (or re-activates) the phone for this install and mints a fresh token pair.
    #
    # E6: the same install signing in again reuses its row rather than adding a second one.
    # E5: beyond MAX_LIVE_DEVICES live phones, the least recently used is signed out.
    #
    # @return [Array(MobileDevice, Devise::Api::Token)]
    def register!(user, install_id:, platform:, name: nil, app_version: nil)
      ActiveRecord::Base.connected_to(role: :writing) do
        transaction do
          # Serialise concurrent sign-ins for one user so two of them cannot both slip past the
          # device limit or both insert the same install.
          user.lock!

          device = find_or_initialize_by(user_id: user.id, install_id: install_id.to_s)
          # Revoke whatever token this install held before (E6 — reinstall / re-sign-in)
          device.devise_api_token&.update!(revoked_at: Time.current) if device.devise_api_token&.revoked_at.nil?

          token = mint_token(user)
          device.assign_attributes(platform:, name: name.to_s.truncate(100).presence, app_version:,
                                   region_code: SiteRegistry.current_code, devise_api_token: token,
                                   last_used_at: Time.current, revoked_at: nil, revoked_reason: nil)
          device.save!

          evict_least_recently_used!(user, keep: device)
          [device, token]
        end
      end
    end

    # The live device whose CURRENT token is this access token, or nil (→ 401).
    # X7: a devise-api token that is not bound to a device is refused here.
    # X5/X15: deactivated users and revoked/expired devices are refused here.
    def authenticate(access_token)
      return nil if access_token.blank?

      token = Devise::Api::Token.find_by(access_token: access_token.to_s, revoked_at: nil)
      return nil if token.nil? || token.expired?

      device = live.find_by(devise_api_token_id: token.id)
      return nil if device.nil? || !device.user.active_for_authentication?

      device.touch_last_used!
      device
    end

    # The live device whose current token carries this refresh token, or nil.
    def for_refresh_token(refresh_token)
      return nil if refresh_token.blank?

      token = Devise::Api::Token.find_by(refresh_token: refresh_token.to_s, revoked_at: nil)
      token && live.find_by(devise_api_token_id: token.id)
    end

    # Signs every live phone of a user out (password change, deactivation — X5, X6)
    def revoke_all_for!(user, reason:)
      where(user_id: user.id, revoked_at: nil).find_each { |device| device.revoke!(reason:) }
    end

    private

    def mint_token(user)
      Devise::Api::Token.create!(
        resource_owner: user,
        access_token: Devise::Api::Token.generate_uniq_access_token(user),
        refresh_token: Devise::Api::Token.generate_uniq_refresh_token(user),
        expires_in: ACCESS_TOKEN_TTL.to_i
      )
    end

    # E5: keep at most MAX_LIVE_DEVICES live phones, signing out the least recently used first
    def evict_least_recently_used!(user, keep:)
      extra = live.where(user_id: user.id).where.not(id: keep.id)
                  .order(last_used_at: :desc).offset(MAX_LIVE_DEVICES - 1)
      extra.each { |device| device.revoke!(reason: "device_limit") }
    end
  end

  def live?
    revoked_at.nil? && last_used_at.present? && last_used_at >= SESSION_LIFETIME.ago
  end

  # Ends this phone's session and stops its pushes in one write (H14 website sign-out, X15)
  def revoke!(reason:)
    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        devise_api_token&.update!(revoked_at: Time.current) if devise_api_token&.revoked_at.nil?
        update!(revoked_at: Time.current, revoked_reason: reason, push_token: nil, push_status: "none")
      end
    end
    true
  end

  # Rotates the token pair for a live device (H3). The old access and refresh tokens stop
  # working immediately.
  def refresh!
    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        lock!
        old = devise_api_token
        token = self.class.send(:mint_token, user)
        token.update!(previous_refresh_token: old&.refresh_token)
        old&.update!(revoked_at: Time.current)
        update!(devise_api_token: token, last_used_at: Time.current)
        token
      end
    end
  end

  # Stores this phone's push address. An address already held by another row (the same phone,
  # now signed in as someone else) moves here, so the previous user's pushes stop reaching it (E7).
  def update_push!(token: nil, enabled: nil, app_version: nil)
    ActiveRecord::Base.connected_to(role: :writing) do
      transaction do
        if token.present? && token != push_token
          self.class.where(push_token: token).where.not(id:).update_all(push_token: nil, push_status: "none", updated_at: Time.current)
          self.push_token = token
          self.push_status = "ok"
        end
        self.push_enabled = ActiveModel::Type::Boolean.new.cast(enabled) unless enabled.nil?
        self.app_version = app_version if app_version.present?
        save!
      end
    end
    self
  rescue ActiveRecord::RecordNotUnique
    # Two phones raced for the same address — the other write won; retry once against it
    @push_retry = !@push_retry
    retry if @push_retry
    raise
  end

  # X10: Expo says this address is dead (app uninstalled / reinstalled)
  def mark_not_registered!
    ActiveRecord::Base.connected_to(role: :writing) { update!(push_status: "not_registered") }
  end

  def touch_last_used!
    return if last_used_at.present? && last_used_at > TOUCH_INTERVAL.ago

    ActiveRecord::Base.connected_to(role: :writing) { update_column(:last_used_at, Time.current) }
  end
end
