# ② One per entity: how the entity's own data maps to pack inputs, its dated reference lists,
# the compliance owner, AI settings and the monitoring switch.
#
# input_mappings  {"sponsor" => {"categories" => ["Sponsor"]}, "ic_note" => {"tag" => "IC Note"},
#                  "est_expenses" => {"<fund_id>" => 300000000.0}}
# reference_lists {"ic_members" => {"quorum" => 3, "entries" => [{"name" => "A. Rao", "valid_from" => nil, "valid_to" => nil}]}}
#
# Worked examples H17, X15, E14, X16, H60, E105, H56, E133 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceEntitySetup < ApplicationRecord
  belongs_to :entity
  belongs_to :owner, class_name: "User", optional: true

  audited

  attr_readonly :entity_id

  validates :entity_id, uniqueness: true

  # ⑩ H87 / E190: the welcome goes out once, when the firm's setup row is first created (R155)
  after_create_commit { ComplianceOnboardingNotices.welcome(self) }
  validate :owner_in_same_firm
  validate :reference_lists_valid

  # One setup per entity. Reads never write (GET requests run read-only): an entity without a setup
  # gets an unsaved one, persisted on its first save.
  def self.for(entity)
    find_by(entity_id: entity.id) || new(entity_id: entity.id)
  end

  def input_mappings_hash
    if input_mappings.is_a?(Hash)
      input_mappings
    else
      (input_mappings.present? ? JSON.parse(input_mappings) : {})
    end
  end

  # {"welcome_sent_on" => "2026-11-04", "reminders_sent" => [7]} — only notice dates; step progress is
  # never stored (D14)
  def onboarding_hash
    if onboarding.is_a?(Hash)
      onboarding
    else
      (onboarding.present? ? JSON.parse(onboarding) : {})
    end
  end

  def reference_lists_hash
    if reference_lists.is_a?(Hash)
      reference_lists
    else
      (reference_lists.present? ? JSON.parse(reference_lists) : {})
    end
  end

  def ai_settings_hash
    if ai_settings.is_a?(Hash)
      ai_settings
    else
      (ai_settings.present? ? JSON.parse(ai_settings) : {})
    end
  end

  # The investor categories mapped to a group input (e.g. "sponsor"); nil when unmapped (X29)
  def group_categories(key)
    cats = Array(input_mappings_hash.dig(key.to_s, "categories")).compact_blank
    cats.presence
  end

  # A per-fund figure input (e.g. estimated expenses); nil when blank (X24)
  def fund_figure(key, fund)
    value = input_mappings_hash.dig(key.to_s, fund.id.to_s)
    value.presence && value.to_d
  end

  # The document mapping for a document input (tag / name / folder) — nil when unmapped
  def document_mapping(key)
    m = input_mappings_hash[key.to_s]
    m.is_a?(Hash) && (m["tag"].present? || m["name"].present?) ? m : nil
  end

  def set_mapping(key, value)
    self.input_mappings = input_mappings_hash.merge(key.to_s => value)
  end

  def set_fund_figure(key, fund, value)
    current = input_mappings_hash[key.to_s].is_a?(Hash) ? input_mappings_hash[key.to_s] : {}
    set_mapping(key, current.merge(fund.id.to_s => value.presence && value.to_d.to_s))
  end

  # Entries of a reference list as they stood on a date — from/to inclusive, blank = always (R1, R28)
  # Worked examples H54, E103, E104, E105
  def reference_list(key, on: nil)
    entries = Array(reference_lists_hash.dig(key.to_s, "entries"))
    return entries.pluck("name") if on.nil?

    entries.select do |e|
      from = e["valid_from"].presence && Date.parse(e["valid_from"].to_s)
      to = e["valid_to"].presence && Date.parse(e["valid_to"].to_s)
      (from.nil? || on >= from) && (to.nil? || on <= to)
    end.pluck("name")
  end

  def quorum(key = "ic_members")
    reference_lists_hash.dig(key.to_s, "quorum")&.to_i
  end

  def set_reference_list(key, entries:, quorum: nil)
    list = { "entries" => entries.map { |e| e.stringify_keys.slice("name", "valid_from", "valid_to") } }
    list["quorum"] = quorum.to_i if quorum.present?
    self.reference_lists = reference_lists_hash.merge(key.to_s => list)
  end

  def ai_drafting_enabled?
    ai_settings_hash["drafting"] == true
  end

  private

  def owner_in_same_firm
    return if owner.nil? || owner.entity_id == entity_id

    errors.add(:owner, "must be a user of your firm")
  end

  # E14, X16: quorum cannot exceed the number of members; "to" after "from"
  def reference_lists_valid
    reference_lists_hash.each do |key, list|
      entries = Array(list["entries"])
      errors.add(:base, "Quorum cannot exceed #{entries.size} members") if list["quorum"].present? && list["quorum"].to_i > entries.size
      entries.each do |e|
        next if e["valid_from"].blank? || e["valid_to"].blank?
        next if Date.parse(e["valid_to"].to_s) >= Date.parse(e["valid_from"].to_s)

        errors.add(:base, "#{e['name']}: \"to\" must be after \"from\" in #{key.humanize}")
      end
    end
  end
end
