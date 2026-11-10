# frozen_string_literal: true

# ③ The change record (OWASP review 2026-11 M14, openspec/changes/archive/2026-11-10-bank-detail-change-controls, design card ③, D6,
# D19; LLD "Schema Detail", "Method Contracts › BankDetailChange").
#
# One row per bank change of a KYC: who made it (a firm user, an investor, or nil = System), how, the last 4 digits
# of the old and new accounts, the old and new IFSC (a public branch code, shown in full), and its state:
#
#   awaiting ──(a second person verifies the KYC)──▶ confirmed
#   awaiting ──(the only approver verifies)────────▶ confirmed (only_approver)
#   awaiting ──(a newer bank change is saved)──────▶ replaced
#
# Written only by BankDetailChangeGuard (②) inside the KYC's own save; rows are never deleted or re-pointed, only
# moved forward (audited). Full account numbers are never stored here (E23) — the KYC's audit trail keeps them.
class BankDetailChange < ApplicationRecord
  include Trackable.new

  STATUSES = %w[awaiting confirmed replaced].freeze
  SIDES = %w[investor fund system].freeze

  belongs_to :entity
  belongs_to :investor_kyc
  belongs_to :changed_by, class_name: "User", optional: true
  belongs_to :confirmed_by, class_name: "User", optional: true

  # Tenant and KYC never change after the row is written (design Security #2)
  attr_readonly :entity_id, :investor_kyc_id

  # Who was emailed about the change (investor contacts' user ids), shown in the note, popup and approver email
  serialize :investor_recipient_ids, type: Array

  validates :status, inclusion: { in: STATUSES }
  validates :changed_by_side, inclusion: { in: SIDES }
  validates :source, inclusion: { in: BankDetailChangeGuard::BANK_CHANGE_SOURCES }
  validates :changed_fields, presence: true, length: { maximum: 100 }
  validates :old_account_last4, :new_account_last4, length: { maximum: 4 }
  validates :old_ifsc, :new_ifsc, length: { maximum: 20 }

  scope :awaiting, -> { where(status: "awaiting") }

  def awaiting?
    status == "awaiting"
  end

  def confirmed?
    status == "confirmed"
  end

  # H9, H10, E45 — a permitted Verify confirms the awaiting change (guard ②). Only an awaiting row moves, so a
  # second Verify of the same change finds nothing to confirm (X12). H11 — only_approver marks a self-confirmation.
  def confirm!(by:, only_approver: false)
    return self unless awaiting?

    update!(status: "confirmed", confirmed_by: by, confirmed_at: Time.current, only_approver: only_approver == true)
    self
  end

  # E15 — a newer bank change overtakes this one before anyone verified it
  def replace!
    return self unless awaiting?

    update!(status: "replaced")
    self
  end

  # How the change was made, as the approver email and the popup say it (design card ①)
  SOURCE_LABELS = { "screen" => "on the KYC form", "api" => "through the API", "import" => "by an import",
                    "document_checks" => "from Document Checks", "ai_extraction" => "by AI document extraction" }.freeze

  def source_label
    SOURCE_LABELS[source]
  end

  # The maker as people see it: "Meera Shah", "Anil Kumar" or "System" (E18 — background work with nobody behind it)
  def maker_name
    changed_by&.full_name || "System"
  end

  def account_changed?
    changed_fields.to_s.split(",").include?("bank_account_number")
  end

  def ifsc_changed?
    changed_fields.to_s.split(",").include?("ifsc_code")
  end

  # "ending 4821" / "none" (E16 — the account was cleared)
  def old_account_display
    old_account_last4.present? ? "ending #{old_account_last4}" : "none"
  end

  def new_account_display
    new_account_last4.present? ? "ending #{new_account_last4}" : "none"
  end

  # One line per changed item, for the KYC page note and the popup: "account ending 4821 → 7310",
  # "IFSC HDFC0001234 → ICIC0004567" (H5, E15, E16)
  def change_lines
    lines = []
    lines << "account #{old_account_display} → #{new_account_last4.presence || 'none'}" if account_changed?
    lines << "IFSC #{old_ifsc.presence || 'none'} → #{new_ifsc.presence || 'none'}" if ifsc_changed?
    lines + custom_field_lines
  end

  # The same lines as the emails write them: "account ending 4821 → ending 7310" (H7)
  def email_change_lines
    lines = []
    lines << "account #{old_account_display} → #{new_account_display}" if account_changed?
    lines << "IFSC #{old_ifsc.presence || 'none'} → #{new_ifsc.presence || 'none'}" if ifsc_changed?
    lines + custom_field_lines
  end

  # D19, H19, H20, E69 — one line per changed payout custom field, by the label it had at change time: a bank code
  # in full ("SWIFT Code EBILAEADXXX → NBADAEAAXXX"), an account identifier by its last 4 ("IBAN ending 3456 →
  # ending 8901"; "none" when blank)
  def custom_field_lines
    Array(changed_custom_fields).map do |item|
      if item["kind"] == "account"
        "#{item['label']} #{item['old'] ? "ending #{item['old']}" : 'none'} → #{item['new'] ? "ending #{item['new']}" : 'none'}"
      else
        "#{item['label']} #{item['old'] || 'none'} → #{item['new'] || 'none'}"
      end
    end
  end

  # H21 — the new values of the changed payout custom fields, for the popup's account card: "SWIFT Code
  # NBADAEAAXXX", "IBAN ••••8901"
  def custom_field_new_values
    Array(changed_custom_fields).filter_map do |item|
      next if item["new"].blank?

      item["kind"] == "account" ? "#{item['label']} ••••#{item['new']}" : "#{item['label']} #{item['new']}"
    end
  end

  # The investor contacts who were emailed (empty when none could be, X6)
  def investor_recipients
    ids = Array(investor_recipient_ids)
    ids.empty? ? User.none : User.where(id: ids).order(:email)
  end

  def investor_recipient_emails
    investor_recipients.pluck(:email)
  end
end
