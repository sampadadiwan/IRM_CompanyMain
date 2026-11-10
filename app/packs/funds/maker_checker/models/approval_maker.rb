# frozen_string_literal: true

# ③ Preparer log (OWASP review 2026-11 M13, openspec/changes/capital-call-distribution-maker-checker, D2).
#
# One row per person who prepared a capital call or distribution: created it, imported it, or changed its figures
# (or the figures of its remittances / payments / fee lines). With the firm's maker–checker setting on, none of these
# people may approve the record (MakerCheckerPolicyMethods). The record's create-audit user also counts (D4), so
# records created before this table existed need no backfill.
#
# Append-only: rows are inserted by WithApprovalMakers#record_preparer! (never from params) and never updated. They
# go only with the record itself (dependent: :delete_all on a hard delete).
class ApprovalMaker < ApplicationRecord
  # How the person became a preparer — shown in the "Prepared by" tooltip; the approval rule ignores it
  ROLES = %w[created edited imported].freeze

  belongs_to :entity
  belongs_to :user
  belongs_to :approvable, polymorphic: true

  validates :approvable_type, length: { maximum: 40 }
  validates :role, inclusion: { in: ROLES }, length: { maximum: 20 }

  # Append-only: a saved row can't be changed
  def readonly?
    persisted? || super
  end
end
