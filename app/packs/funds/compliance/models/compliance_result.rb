# ⑤ One check outcome — append-only. The only column ever updated is superseded_reason, once (R14).
# outcome: pass / breach / warning / needs_review / could_not_check
# Worked examples H20, E20, X66, H57, X67 — openspec/changes/archive/2026-11-06-fund-compliance-monitoring/business-rules.md
class ComplianceResult < ApplicationRecord
  OUTCOMES = %w[pass breach warning needs_review could_not_check].freeze

  belongs_to :entity
  belongs_to :compliance_run
  belongs_to :fund_compliance_pack
  belongs_to :compliance_pack_version

  attr_readonly :entity_id

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :check_key, presence: true

  # Results are a historical record — never rewritten (E20, X66)
  before_update :only_superseded_reason_changes
  before_destroy { throw :abort }

  def working_hash
    if working.is_a?(Hash)
      working
    else
      (working.present? ? JSON.parse(working) : {})
    end
  end

  def superseded?
    superseded_reason.present?
  end

  # "Superseded — pack correction" once, never cleared (X67)
  def supersede!(reason = "pack_correction")
    return if superseded?

    update_columns(superseded_reason: reason, updated_at: Time.current)
  end

  delegate :run_date, to: :compliance_run

  def message
    working_hash["message"]
  end

  private

  def only_superseded_reason_changes
    allowed = %w[superseded_reason updated_at]
    return if (changed - allowed).empty? && superseded_reason_was.nil?

    raise ActiveRecord::ReadOnlyRecord, "Compliance results are append-only"
  end
end
