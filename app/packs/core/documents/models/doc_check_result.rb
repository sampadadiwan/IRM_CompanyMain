# One check's outcome in one run: OK, or the reason it needs attention, with both values and the AI's
# explanation. A person resolves it on the spot — Use document value, or Mark as OK with a reason (which
# Undo clears). Resolutions are stamps on the row, not statuses.
# See openspec/changes/document-checks/design.md (cards ⑥ Judge and ⑦ Results).
class DocCheckResult < ApplicationRecord
  OUTCOMES = %w[ok mismatch kyc_blank not_found bad_date unexpected_answer not_uploaded unreadable_file
                unreadable_reply field_missing].freeze
  # Outcomes that apply to a whole document (one line per document in the tab)
  DOCUMENT_OUTCOMES = %w[not_uploaded unreadable_file unreadable_reply].freeze
  # Use document value: only a Compare that read a value
  USE_VALUE_OUTCOMES = %w[mismatch kyc_blank].freeze
  # Mark as OK: not for things a click can't settle (upload, unreadable, removed field)
  MARK_OK_OUTCOMES = %w[mismatch kyc_blank not_found bad_date unexpected_answer].freeze
  # The attention list's reason filter -> outcome codes
  REASONS = {
    "doesnt_match" => %w[mismatch kyc_blank],
    "not_found" => %w[not_found bad_date],
    "unexpected_answer" => %w[unexpected_answer],
    "couldnt_read" => %w[unreadable_file unreadable_reply field_missing],
    "not_uploaded" => %w[not_uploaded]
  }.freeze

  belongs_to :entity
  belongs_to :doc_check_run, inverse_of: :doc_check_results
  belongs_to :doc_check, optional: true
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :outcome, inclusion: { in: OUTCOMES }
  validates :resolution, inclusion: { in: %w[marked_ok used_document_value] }, allow_nil: true
  validates :resolve_reason, length: { maximum: 255 }

  scope :needing_attention, -> { where(resolution: nil).where.not(outcome: "ok") }

  def ok?
    outcome == "ok" || resolution.present?
  end

  def needs_attention?
    !ok?
  end

  def document_level?
    DOCUMENT_OUTCOMES.include?(outcome)
  end

  def can_use_document_value?
    needs_attention? && USE_VALUE_OUTCOMES.include?(outcome) && doc_value.present? && field_name.present?
  end

  def can_mark_ok?
    needs_attention? && MARK_OK_OUTCOMES.include?(outcome)
  end

  def can_undo?
    resolution == "marked_ok"
  end

  delegate :record, to: :doc_check_run

  # Mark as OK with a reason. Worked examples H6, X8 — openspec/changes/document-checks/design.md#worked-examples
  def mark_ok!(user:, reason:)
    reason = reason.to_s.squish
    with_lock do
      refuse!(:resolve_reason, "Say why this is OK") if reason.blank?
      refuse!(:resolution, "This item can't be marked OK") unless can_mark_ok? && doc_check_run.current?
      update!(resolution: "marked_ok", resolved_by: user, resolved_at: Time.current, resolve_reason: reason)
    end
  end

  # Undo a Mark as OK: back to its original reason. Worked example E19.
  def undo!
    with_lock do
      refuse!(:resolution, "Only a marked-OK item can be undone") unless can_undo?
      update!(resolution: nil, resolved_by: nil, resolved_at: nil, resolve_reason: nil)
    end
  end

  # Copy the document's value into the record's field (audited), then stamp the row. The journey hook
  # runs after commit. Lock order: result, then record — the same everywhere.
  # Worked example H5 — openspec/changes/document-checks/design.md#worked-examples
  def use_document_value!(user:)
    entry = DocChecks::Registry.for(doc_check_run.record_type)
    target = record
    transaction do
      lock!
      refuse!(:resolution, "This item can't use the document's value") unless can_use_document_value? && doc_check_run.current?
      field = entry.field(target.entity, field_name)
      refuse!(:field_name, "This check's KYC field no longer exists") unless field
      target.lock!
      entry.write(target, field, doc_value)
      entry.save_details!(target)
      update!(resolution: "used_document_value", resolved_by: user, resolved_at: Time.current, record_value: doc_value)
    end
    entry.details_changed!(target, user:)
    true
  end

  private

  def refuse!(attribute, message)
    errors.add(attribute, message)
    raise ActiveRecord::RecordInvalid, self
  end
end
