# ⑧ One "Describe in words" draft: the sentence, what was sent to the AI, the AI's structured draft
# (edited field by field), and its test run. Nothing here is a check until the user presses Save,
# which appends the check (or duty) to the pack version's draft definition with its provenance.
#
# draft (structured fields only — never formula code; X40):
#   {"kind" => "limit" | "duty", "name", "citation",
#    "figure" => {"measure" => "cost_per_sector"} | {"op","source","field","group_by","filters" => [{"field","op","value"}]},
#    "divided_by" => same | nil, "compare" => "lte", "limit_value" => 15, "limit_unit" => "pct",
#    "duty_trigger" => "on_demand" | "quarterly" | "half_yearly" | "yearly", "duty_due_days", "evidence",
#    "reason" => "CapHive does not record key-person events", "assumptions" => [{"part","text"}]}
#
# Worked examples H37, H38, H39, E57–E62, X39–X42 — openspec/changes/fund-compliance-monitoring/business-rules.md
class ComplianceCheckDraft < ApplicationRecord
  MAX_SENTENCE = 1_000
  STATUSES = %w[drafting ready saved failed].freeze
  PARTS = %w[figure divided_by].freeze
  DUTY_TRIGGERS = %w[on_demand quarterly half_yearly yearly].freeze

  belongs_to :entity, optional: true
  belongs_to :compliance_pack_version
  belongs_to :user
  belongs_to :test_fund, class_name: "Fund", optional: true

  attr_readonly :entity_id, :compliance_pack_version_id, :user_id

  validates :status, inclusion: { in: STATUSES }
  # E62 / X39: the sentence must be present and at most 1,000 characters
  validates :sentence, presence: { message: "Describe the rule first" }
  validate :sentence_length
  validate :same_firm_as_pack

  delegate :compliance_pack, to: :compliance_pack_version

  def draft_hash
    (draft.is_a?(String) ? JSON.parse(draft) : draft) || {}
  end

  def test_result_hash
    (test_result.is_a?(String) ? JSON.parse(test_result) : test_result) || {}
  end

  def ready?
    status == "ready"
  end

  def saved?
    status == "saved"
  end

  def duty?
    draft_hash["kind"] == "duty"
  end

  # E59: Save stays disabled until the draft has been tested since the last edit
  def tested?
    test_result_hash.present?
  end

  def assumptions
    Array(draft_hash["assumptions"]).select { |a| a.is_a?(Hash) && a["text"].present? }
  end

  # ── The draft as definition JSON ─────────────────────────────────────────────────────────
  # The check (or duty) plus any new measures, keyed so nothing collides with the version's own keys.
  def fragment(version = compliance_pack_version)
    d = draft_hash
    existing = version.definition_hash
    return { "duty" => duty_fragment(d, existing), "measures" => [] } if duty?

    measures = []
    figure_key = measure_ref(d["figure"], existing, measures, "figure")
    divisor_key = d["divided_by"].is_a?(Hash) ? measure_ref(d["divided_by"], existing, measures, "divided_by") : nil
    { "check" => check_fragment(d, existing, figure_key, divisor_key), "measures" => measures }
  end

  # The version's definition with this draft added — what the validator, the test run and Save all use
  def merged_definition(version = compliance_pack_version)
    defn = version.definition_hash.deep_dup
    frag = fragment(version)
    defn["measures"] = Array(defn["measures"]) + frag["measures"]
    if frag["duty"]
      defn["duties"] = Array(defn["duties"]) + [frag["duty"]]
    else
      defn["checks"] = Array(defn["checks"]) + [frag["check"]]
    end
    defn
  end

  # X40: validated exactly like a form-built check — "Unknown field: lp_tier" blocks Save
  def validation_errors
    return ["Drafting is not finished"] unless ready? || saved?

    ComplianceDefinitionValidator.call(merged_definition, caphive: compliance_pack.caphive?)
  rescue StandardError => e
    ["Draft could not be read (#{e.class.name.demodulize})"]
  end

  # A pack version holding the merged definition, never saved — used for the test run and plain words
  def preview_version
    version = compliance_pack_version
    CompliancePackVersion.new(compliance_pack: version.compliance_pack, version_no: version.version_no,
                              applicability: "all", status: "draft", definition: merged_definition)
  end

  # The key the drafted check or duty will have once saved
  def drafted_key
    frag = fragment
    (frag["duty"] || frag["check"])["key"]
  end

  # Save appends the check (or duty) to the version's draft with its provenance (H38).
  # Refused until tested since the last edit (E59) and while the validator objects (X40).
  # Returns the list of errors — empty when saved.
  def save_into_version!(user)
    errors = validation_errors
    errors << "Run a test first" unless tested?
    errors << "Only a draft version can take new checks" unless compliance_pack_version.draft?
    return errors if errors.any?

    version = compliance_pack_version
    key = drafted_key
    definition = merged_definition
    entry = (Array(definition["checks"]) + Array(definition["duties"])).detect { |c| c["key"] == key }
    entry["drafted_with_ai"] = { "sentence" => sentence, "confirmed_by_id" => user.id,
                                 "confirmed_by" => user.full_name, "confirmed_on" => Time.zone.today.iso8601 }
    transaction do
      version.definition = definition
      version.save!
      update!(status: "saved", saved_check_key: key)
    end
    []
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.full_messages
  end

  private

  def sentence_length
    errors.add(:sentence, "Keep the rule under 1,000 characters") if sentence.to_s.length > MAX_SENTENCE
  end

  def same_firm_as_pack
    pack = compliance_pack_version&.compliance_pack
    return if pack.nil? || pack.entity_id.nil? || pack.entity_id == entity_id

    errors.add(:base, "Pack belongs to another firm")
  end

  # A part names an existing measure, or describes a new one that is added with a fresh key
  def measure_ref(part, existing, measures, role)
    part = {} unless part.is_a?(Hash)
    return part["measure"].to_s if part["measure"].present?

    measure = part.slice("op", "source", "field", "group_by").compact_blank
    filters = Array(part["filters"]).filter_map do |f|
      f.is_a?(Hash) ? [f["field"].to_s, f["op"].to_s, f["value"]] : Array(f).first(3)
    end
    measure["filters"] = filters if filters.any?
    measure["key"] = unique_key("#{base_key}_#{role}", Array(existing["measures"]).pluck("key") + measures.pluck("key"))
    measure["label"] = part["label"].presence || ComplianceCheckDraftWords.part(nil, part)
    measures << measure
    measure["key"]
  end

  def check_fragment(draft, existing, figure_key, divisor_key)
    check = {
      "key" => unique_key(base_key, Array(existing["checks"]).pluck("key")),
      "name" => draft["name"].presence || sentence.to_s.truncate(60),
      "kind" => "limit", "applies_to" => "all",
      "figure" => divisor_key ? ["/", figure_key, divisor_key] : figure_key,
      "compare" => draft["compare"].presence || "lte",
      "limit" => { "value" => draft["limit_value"], "unit" => draft["limit_unit"].presence || "pct" },
      "tested" => "continuous", "override" => "any", "time_to_fix_days" => 30, "severity" => "breach"
    }
    check["citation"] = draft["citation"] if draft["citation"].present?
    # H91: saved with its plain-words description (R158)
    check["description"] = draft["description"] if draft["description"].present?
    check
  end

  # H39: a rule CapHive cannot check from data becomes a manual duty (evidence required)
  def duty_fragment(draft, existing)
    trigger = DUTY_TRIGGERS.include?(draft["duty_trigger"]) ? draft["duty_trigger"] : "on_demand"
    duty = { "key" => unique_key(base_key, Array(existing["duties"]).pluck("key")),
             "name" => draft["name"].presence || sentence.to_s.truncate(60),
             "trigger" => trigger == "on_demand" ? { "on_demand" => true } : { "schedule" => trigger },
             "evidence" => draft["evidence"] != false, "applies_to" => "all" }
    duty["due"] = { "days_after" => "period_end", "n" => draft["duty_due_days"].to_i } if trigger != "on_demand"
    duty["reason"] = draft["reason"] if draft["reason"].present?
    duty["citation"] = draft["citation"] if draft["citation"].present?
    duty["description"] = draft["description"] if draft["description"].present?
    duty
  end

  def base_key
    slug = draft_hash["name"].to_s.parameterize(separator: "_").first(40).presence || "drafted"
    "ai_#{slug}"
  end

  def unique_key(key, taken)
    return key unless taken.include?(key)

    (2..).each { |n| return "#{key}_#{n}" unless taken.include?("#{key}_#{n}") }
  end
end
