# CanonicalFingerprint — Problem & Solution
# -----------------------------------------------------------------------------
# PROBLEM
# CapHive runs multiple regional Rails instances (e.g., US/IN/SG). A user can
# access several regions (`regions`) but has one authoritative home region
# (`primary_region`). We must sync a user to non-primary regions ONLY when
# their canonical state changes (key profile fields, role assignments, or
# entity pointer) — *not* on arbitrary updates, so `updated_at` is unusable.
#
# SOLUTION
# Compute a deterministic Canonical Change Fingerprint (CCF) as a SHA-256 hex
# over:
#   1) Normalized KEY_USER_FIELDS (incl. `primary_region`, email, etc.)
#   2) Normalized, order-insensitive ROLE tuples (ROLE_ITEM_FIELDS)
#   3) A stable entity pointer (uid/slug, with local id fallback)
# Persist the last published fingerprint in `last_synced_ccf_hex`.
#
# DECISION RULE
# `needs_sync?` => true IFF:
#   - There is at least one non-primary target (regions − primary_region), AND
#   - `ccf_hex != last_synced_ccf_hex` (or no prior sync)
# After you actually fan out the change, call `mark_synced_now!`.
#
# GUARANTEES
# - Ignores noise (non-canonical fields) and record order (roles are sorted)
# - Idempotent (replays yield same CCF)
# - Deterministic JSON serialization with key sorting
#
# CUSTOMIZATION
# - Adjust KEY_USER_FIELDS / ROLE_ITEM_FIELDS to your schema & scoping
# - Override `entity_global_key` if you standardize an entity UID

require "digest"
require "json"

module CanonicalFingerprint
  extend ActiveSupport::Concern

  # The fields that contribute to the canonical fingerprint.
  KEY_USER_FIELDS = %i[email first_name last_name call_code phone primary_region regions entity_type].freeze
  KEY_ENTITY_FIELDS = %i[name entity_type].freeze
  ROLE_ITEM_FIELDS = %i[name].freeze

  # ---- Public API ----

  # True only if there is at least one non-primary target region AND the canonical state changed.
  def needs_sync?
    non_primary_regions.any? && (last_synced_ccf_hex.blank? || ccf_hex != last_synced_ccf_hex)
  end

  # Current canonical fingerprint (hex, 64 chars)
  def ccf_hex
    Digest::SHA256.hexdigest(user_block_string + roles_block_string)
  end

  # Persist snapshot AFTER you actually fan out the change.
  # rubocop:disable Rails/SkipsModelValidations
  def mark_synced_now!
    update_columns(
      last_synced_ccf_hex: ccf_hex,
      last_synced_at: Time.current
    )
  end
  # rubocop:enable Rails/SkipsModelValidations

  # ---- Regions helpers ----

  # Regions excluding the primary one (targets to sync to)
  def non_primary_regions
    arr = normalize_regions_array(regions)
    pr  = normalize_region(primary_region)
    arr.reject { |r| r == pr }
  end

  # ---- Canonical blocks (deterministic strings) ----

  def user_block_string
    payload = {}
    KEY_USER_FIELDS.each { |attr| payload[attr.to_s] = normalize_field(attr, read_attribute(attr)) }

    # Include entity fields if entity is present
    if respond_to?(:entity) && entity
      KEY_ENTITY_FIELDS.each do |attr|
        payload[attr.to_s] = normalize_field(attr, entity.public_send(attr)) if entity.respond_to?(attr)
      end
    end

    stable_json(payload)
  end

  def roles_block_string
    # Order-insensitive set of role tuples
    role_items = (respond_to?(:roles) ? roles : []).map do |role|
      ROLE_ITEM_FIELDS.map { |f| normalize_field(f, role.public_send(f)) }
    end

    role_items = role_items.uniq.sort_by { |tuple| tuple.map(&:to_s) }
    stable_json(role_items)
  end

  # ---- Normalization ----

  def normalize_field(attr, value)
    return nil if value.nil?

    case attr.to_s
    when "email" then value.to_s.strip.downcase
    when "phone"
      normalized_phone = value.to_s.gsub(/\D/, "") # Remove all non-digit characters
      normalized_phone.presence # Return nil if empty after normalization
    when "name" then value.to_s.strip.squeeze(" ")
    when "locale", "timezone", "status", "primary_region"
      value.to_s.strip
    else
      value.is_a?(String) ? value.strip : value
    end
  end

  def normalize_regions_array(regions_input)
    regions_array = begin
      # Attempt to parse as JSON array first
      parsed = JSON.parse(regions_input.to_s)
      parsed.is_a?(Array) ? parsed : regions_input.to_s.split(",")
    rescue JSON::ParserError
      # If not a valid JSON, treat as a comma-separated string
      regions_input.to_s.split(",")
    end

    regions_array.filter_map { |s| normalize_region(s) }.uniq.sort
  end

  def normalize_region(region)
    region.present? ? region.to_s.strip.upcase : nil
  end

  # Deterministic JSON (sorted keys)
  def stable_json(obj)
    JSON.generate(stabilize(obj))
  end

  def stabilize(obj)
    case obj
    when Hash
      obj.keys.map(&:to_s).sort.index_with { |k| stabilize(obj[k] || obj[k.to_sym]) }
    when Array
      obj.map { |e| stabilize(e) }
    else
      obj
    end
  end
end
