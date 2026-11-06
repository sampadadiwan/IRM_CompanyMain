# ⑧ The document inputs an entity's attached packs ask AI to read: for each input key, the facts declared
# across the current versions of the entity's active fund packs (union by key — the entity maps an input
# key to one tag or name, so every pack using "ic_note" reads the same documents), and any "notes" request
# (kind-4 duties: AI prepares, a person decides — H44).
# The facts signature is a hash of the declared fact keys: a version adding a fact changes it (R17, E130).
# Worked examples H40, H44, E130, X44 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceDocumentInputs
  Input = Struct.new(:key, :label, :facts, :notes, keyword_init: true) do
    def fact_keys
      facts.pluck("key")
    end

    def signature
      DocumentReading.signature_for(fact_keys + (notes.present? ? ["__notes__"] : []))
    end

    def fact(key)
      facts.detect { |f| f["key"] == key }
    end

    def readable?
      facts.any? || notes.present?
    end
  end

  # Record types a mapped document input can be attached to (the catalogue's sources plus the fund itself)
  OWNER_TYPES = %w[PortfolioInvestment InvestorKyc CapitalCommitment Fund].freeze

  def self.for(entity)
    new(entity).inputs
  end

  def self.find(entity, key)
    self.for(entity)[key.to_s]
  end

  # Declared facts of one input in one version (what a content check of that version needs)
  def self.version_facts(version, key)
    inp = version.inputs.detect { |i| i["key"] == key.to_s }
    Array(inp&.dig("facts")).select { |f| f.is_a?(Hash) && f["key"].present? }
  end

  def initialize(entity)
    @entity = entity
  end

  def inputs
    by_key = {}
    FundCompliancePack.active.where(entity_id: @entity.id).includes(:compliance_pack_version).find_each do |fp|
      version = fp.compliance_pack_version
      next if version.nil?

      version.inputs.each do |inp|
        next unless inp["type"] == "document"

        rec = by_key[inp["key"]] ||= Input.new(key: inp["key"], label: inp["label"].presence || inp["key"].humanize, facts: [], notes: nil)
        self.class.version_facts(version, inp["key"]).each do |f|
          rec.facts << f.slice("key", "label", "type") unless rec.fact_keys.include?(f["key"])
        end
        rec.notes ||= inp["notes"].presence
      end
    end
    by_key.select { |_, i| i.readable? }
  end
end
