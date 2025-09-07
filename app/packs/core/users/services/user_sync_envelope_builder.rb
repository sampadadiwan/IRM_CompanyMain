# frozen_string_literal: true

# Builds the canonical, idempotent UPSERT payload that targets will accept.
# Rules (per your spec):
# - Email is immutable; lookup key on the target.
# - Sync ALL user attributes EXCEPT telemetry/secrets (see EXCLUDED_USER_ATTRS).
# - Sync ALL entity attributes (minus local identifiers like id/timestamps).
# - Roles: delete-and-replace on target; here we send role names only.
#
# NOTE: Transport/client is not handled here; this service only constructs payloads.
class UserSyncEnvelopeBuilder
  EXCLUDED_USER_ATTRS = %w[
    id created_at updated_at
    last_sign_in_at current_sign_in_at sign_in_count
    last_sign_in_ip current_sign_in_ip
    failed_attempts unlock_token remember_created_at
    reset_password_token reset_password_sent_at
    encrypted_password password_digest
    otp_secret otp_backup_codes api_token api_tokens invitation_token
  ].freeze

  EXCLUDED_ENTITY_ATTRS = %w[
    id created_at updated_at
  ].freeze

  # @param user [User]
  # @param target_region [String]
  # @param event_id [String,nil]
  # @return [Hash] snapshot envelope ready for JSON encode
  def self.build(user:, target_region:, event_id: nil)
    new(user, target_region, event_id).build
  end

  def initialize(user, target_region, event_id)
    @user          = user
    @target_region = normalize_region(target_region)
    @event_id      = event_id.presence || SecureRandom.uuid
  end

  def build
    {
      action: "UPSERT",
      event_id: @event_id,
      as_of: Time.current.utc.iso8601(3),
      origin_region: normalize_region(@user.primary_region),
      target_region: @target_region,
      ccf_hex: @user.ccf_hex,
      user: user_payload,
      entity: entity_payload,
      roles: roles_payload
    }.compact
  end

  private

  def user_payload
    attrs = @user.attributes.except(*EXCLUDED_USER_ATTRS)
    # Normalize region fields and ensure regions includes primary
    attrs["primary_region"] = normalize_region(attrs["primary_region"])
    attrs["regions"]        = normalize_regions(attrs["regions"])

    attrs
  end

  def entity_payload
    return nil unless @user.respond_to?(:entity) && @user.entity.present?

    # Full entity upsert (minus local identifiers)
    payload = @user.entity.attributes.except(*EXCLUDED_ENTITY_ATTRS)

    # Include a stable cross-region key if you have one; fall back safely.
    payload["key"] = entity_global_key(@user.entity)
    payload
  end

  def roles_payload
    names = if @user.respond_to?(:roles)
              Array(@user.roles).map { |r| r.respond_to?(:name) ? r.name.to_s.strip : nil }
            else
              []
            end

    names.compact.uniq.sort.map { |n| { "name" => n } }
  end

  def entity_global_key(entity)
    if entity.respond_to?(:uid) && entity.uid.present?
      "uid:#{entity.uid}"
    elsif entity.respond_to?(:slug) && entity.slug.present?
      "slug:#{entity.slug}"
    else
      # Fallback: avoid leaking local id across regions if possible.
      # Keep this for now; consider adding a real UID column on entities.
      "local_id:#{entity.id}"
    end
  end

  def normalize_region(region_value)
    region_value.to_s.strip.upcase.presence
  end

  def normalize_regions(regions_input)
    Array(regions_input).filter_map { |r| normalize_region(r) }.uniq.sort
  end
end
