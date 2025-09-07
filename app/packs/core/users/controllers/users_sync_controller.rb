# app/controllers/users_sync_controller.rb
# frozen_string_literal: true

class UsersSyncController < ActionController::API
  before_action :verify_hmac!

  EXCLUDED_USER_ATTRS = %w[
    id created_at updated_at
    last_sign_in_at current_sign_in_at sign_in_count
    last_sign_in_ip current_sign_in_ip
    failed_attempts unlock_token remember_created_at
    reset_password_token reset_password_sent_at
    encrypted_password password_digest otp_secret otp_backup_codes
    api_token api_tokens invitation_token
    last_synced_ccf_hex last_synced_at access_rights_cache entity_id
  ].freeze

  EXCLUDED_ENTITY_ATTRS = %w[id created_at updated_at].freeze

  # POST /internal/sync/users
  # Body: { action:"UPSERT", event_id, as_of, origin_region, target_region, ccf_hex,
  #         user:{...}, entity:{...}, roles:[{name}] }

  # rubocop:disable Rails/SkipsModelValidations
  def upsert
    payload       = parse_json_body!
    origin_region = norm_region(payload["origin_region"])
    ccf_hex       = payload["ccf_hex"].to_s

    ujson = payload["user"] or return render json: { error: "missing_user" }, status: :bad_request
    email = ujson["email"].to_s.strip.downcase
    return render json: { error: "missing_email" }, status: :bad_request if email.blank?

    user = User.find_by(email: email) || User.new(email: email)

    # Primary enforcement if user exists
    return render json: { applied: false, reason: "stale_primary", primary_region: user.primary_region }, status: :conflict if user.persisted? && norm_region(user.primary_region) != origin_region

    # Idempotency (target-side)
    return render json: { applied: false, reason: "no_change", ccf_hex_applied: user.last_synced_ccf_hex }, status: :ok if user.last_synced_ccf_hex.present? && user.last_synced_ccf_hex == ccf_hex

    # ---- Entity: full upsert ----
    if (ejson = payload["entity"]).present?
      entity = find_or_build_entity(ejson)
      apply_entity!(entity, ejson)
      user.entity = entity
    end

    # ---- User: full upsert (minus excluded) ----
    apply_user!(user, ujson)
    user.entity ||= entity

    # ---- Roles: delete & replace (names only) ----
    replace_roles!(user, payload["roles"] || [])

    # Persist + stamp digest atomically
    User.transaction do
      user.save!
      user.update_columns(last_synced_ccf_hex: ccf_hex, last_synced_at: Time.current)
    end

    render json: { applied: true, ccf_hex_applied: ccf_hex, event_id: payload["event_id"] }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { applied: false, reason: "invalid_payload", errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end
  # rubocop:enable Rails/SkipsModelValidations

  # POST /internal/sync/users/disable
  # Body: { action:"DISABLE", event_id, as_of, origin_region, target_region, email, reason }
  def disable
    payload       = parse_json_body!
    origin_region = norm_region(payload["origin_region"])
    email         = payload["email"].to_s.strip.downcase
    return render json: { error: "missing_email" }, status: :bad_request if email.blank?

    user = User.find_by(email: email)
    return render json: { applied: false, reason: "not_found" }, status: :ok unless user

    return render json: { applied: false, reason: "stale_primary", primary_region: user.primary_region }, status: :conflict if norm_region(user.primary_region) != origin_region

    # Soft-disable according to your schema
    user.update!(active: false)

    render json: { applied: true }, status: :ok
  rescue ActiveRecord::RecordInvalid => e
    render json: { applied: false, reason: "invalid_payload", errors: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  # POST /internal/sync/users/digest
  # Body: { emails: ["a@x.com","b@x.com"] }
  # Resp: { digests: { "a@x.com":"...", "b@x.com":null } }
  def digest
    payload = parse_json_body!
    emails  = Array(payload["emails"]).map { |e| e.to_s.strip.downcase }.uniq
    return render json: { error: "missing_emails" }, status: :bad_request if emails.empty?

    rows = User.where(email: emails).pluck(:email, :last_synced_ccf_hex)
    map  = rows.to_h
    out  = emails.index_with { |e| map[e] }

    render json: { digests: out }, status: :ok
  end

  private

  # ---------- Security: HMAC ----------
  def verify_hmac!
    ts  = request.headers["X-Timestamp"].to_s
    sig = request.headers["X-Signature"].to_s
    return render json: { error: "missing_timestamp_or_signature" }, status: :unauthorized if ts.blank? || sig.blank?

    # timestamp skew (±300s)
    begin
      t = Time.iso8601(ts)
    rescue ArgumentError
      return render json: { error: "invalid_timestamp" }, status: :unauthorized
    end
    return render json: { error: "stale_timestamp" }, status: :unauthorized if (Time.now.utc - t).abs > 300

    origin_region_from_header = request.headers["X-Region"].to_s.strip.upcase
    secret = hmac_secret_for(origin_region_from_header)
    return render json: { error: "server_misconfigured" }, status: :unauthorized if secret.blank?

    data   = "#{request.request_method.upcase}\n#{request.path}\n#{ts}\n#{Digest::SHA256.hexdigest(request.raw_post.to_s)}"
    expect = OpenSSL::HMAC.hexdigest("SHA256", secret, data)

    render json: { error: "bad_signature" }, status: :forbidden unless ActiveSupport::SecurityUtils.secure_compare(expect, sig)
  end

  def parse_json_body!
    JSON.parse(request.raw_post.to_s)
  rescue JSON::ParserError
    render json: { error: "invalid_json" }, status: :bad_request and return
  end

  # ---------- Apply attributes ----------
  def apply_user!(user, ujson)
    permitted = user.attributes.keys - EXCLUDED_USER_ATTRS
    attrs     = ujson.slice(*permitted)

    # Normalize regions (client sends array; DB may persist CSV string)
    if attrs.key?("regions")
      normalized = normalize_regions(attrs["regions"])
      attrs["regions"] = if user.column_for_attribute("regions").type == :string
                           normalized.join(",")
                         else
                           normalized
                         end
    end
    attrs["primary_region"] = norm_region(attrs["primary_region"]) if attrs.key?("primary_region")

    user.assign_attributes(attrs)
    # Permissions need to set in a special way
    user.permissions = attrs["permissions"].map!(&:to_sym) if attrs["permissions"].is_a?(Array)
    user[:permissions] = attrs["permissions"] if attrs["permissions"].is_a?(Integer) # allow DB-level setting
    user.extended_permissions = attrs["extended_permissions"].map!(&:to_sym) if attrs["extended_permissions"].is_a?(Array)
    user[:extended_permissions] = attrs["extended_permissions"] if attrs["extended_permissions"].is_a?(Integer) # allow DB-level setting

    if user.new_record? && user.respond_to?(:password=) && user.encrypted_password.blank?
      # Set a random password for new users if none provided
      random_password = SecureRandom.hex(16)
      user.password = random_password if user.respond_to?(:password=)
    end
    user
  end

  def find_or_build_entity(ejson)
    key = ejson["key"].to_s
    if key.start_with?("uid:") && Entity.new.respond_to?(:uid)
      Entity.find_by(uid: key.delete_prefix("uid:")) || Entity.new
    elsif key.start_with?("slug:") && Entity.new.respond_to?(:slug)
      Entity.find_by(slug: key.delete_prefix("slug:")) || Entity.new
    elsif ejson["name"] && Entity.column_names.include?("name")
      Entity.find_by(name: ejson["name"]) || Entity.new
    else
      Entity.new
    end
  end

  def apply_entity!(entity, ejson)
    permitted = entity.attributes.keys - EXCLUDED_ENTITY_ATTRS
    attrs     = ejson.slice(*permitted)
    entity.assign_attributes(attrs)
    entity.permissions = attrs["permissions"] if attrs["permissions"].is_a?(Array)
    entity[:permissions] = attrs["permissions"] if attrs["permissions"].is_a?(Integer) # allow DB-level setting
    entity.save! if entity.changed?
  end

  def replace_roles!(user, roles_json)
    names = Array(roles_json).map { |r| (r["name"] || r[:name]).to_s.strip }.compact_blank.uniq.sort

    # Clear
    if user.respond_to?(:roles)
      # Works with rolify-backed or AR-backed roles
      begin
        user.roles = []
      rescue StandardError
        user.roles.destroy_all
      end
    end

    # Add
    names.each do |name|
      if user.respond_to?(:add_role)
        user.add_role(name.to_sym) # rolify
      elsif defined?(Role)
        role = Role.find_or_create_by!(name: name)
        user.roles << role unless user.roles.exists?(role.id)
      end
    end
  end

  # ---------- Normalization & config ----------
  def norm_region(region)
    region.to_s.strip.upcase.presence
  end

  def normalize_regions(regions)
    case regions
    when String then regions.split(/[,\s]+/).filter_map { |r| norm_region(r) }.uniq.sort
    when Array  then regions.filter_map { |r| norm_region(r) }.uniq.sort
    else             Array(regions).filter_map { |r| norm_region(r) }.uniq.sort
    end
  end

  # Which region is THIS server?
  def target_region_code
    ENV["REGION"].presence ||
      begin
        Rails.application.config_for(:sync)["region"]
      rescue StandardError
        nil
      end.presence ||
      "US"
  end

  def hmac_secret_for(region)
    begin
      Rails.application.credentials.dig(:sync_api, :secrets, region)
    rescue StandardError
      nil
    end ||
      ENV.fetch("SYNC_API_HMAC_#{region}", nil)
  end
end
