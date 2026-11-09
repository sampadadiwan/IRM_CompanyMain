# frozen_string_literal: true

# ② The change guard (OWASP review 2026-11 M14, openspec/changes/bank-detail-change-controls, design card ②,
# D1–D5; LLD "Method Contracts › BankDetailChangeGuard", "Transactions").
#
# Included in InvestorKyc. Every way a KYC is saved — the KYC form, the JSON API, imports, Document Checks and AI
# extraction — ends in InvestorKyc#save, so the bank-details rule sits here and no write path can miss it.
#
# In the same save that changes a payout value (account number, IFSC):
#   - Bank Verified goes off and the stored bank check status / response are cleared (H1–H3, E1–E10), whatever
#     value of Bank Verified was sent with the save (E1);
#   - a change from a non-blank value is a *bank change*; on a verified KYC it unverifies the KYC exactly as UnVerify
#     does (E9, E10), and it wins over a verify sent in the same save (a change is never self-confirmed in its own save).
#
# Callers say who made the change (bank_change_actor) and how (bank_change_source); both are attr_accessors, never
# request params. Everything runs inside the caller's transaction, so a failed save changes nothing (X1).
module BankDetailChangeGuard
  extend ActiveSupport::Concern

  # D1 — the columns a payout is routed by. Bank name, branch and account type describe the account; changing them
  # cannot redirect money, so they are not here (E2).
  PAYOUT_FIELDS = %w[bank_account_number ifsc_code].freeze

  # How the change was made, for the record's "how" label (design card ①). Anything else is stored as "other".
  BANK_CHANGE_SOURCES = %w[screen api import document_checks ai_extraction other].freeze

  included do
    # Set by the code that saves the KYC: the person behind the request (D5) and how it was made (card ①)
    attr_accessor :bank_change_actor, :bank_change_source
    # Set by the Verify paths from InvestorKycPolicy#bank_change_only_approver?: the maker verifies because nobody
    # else at the firm can (H11) — recorded on the confirmation
    attr_accessor :bank_change_only_approver
    # Phase 6 — an import run shares one { form type ids => marked keys } memo across its rows (one pluck per form type)
    attr_accessor :bank_change_payout_keys_cache

    # ② Clear the flag and unverify inside the UPDATE itself, so the audit row shows both changes together
    before_save :guard_bank_details
    # ③ Write (or confirm) the change record in the same transaction: a failed save leaves no record (X5)
    after_save :record_bank_change
    # ④ Emails only once the change is committed; never fails the save
    after_commit :notify_bank_change, on: :update
  end

  # Values compared with spaces removed and letters upper-cased: "hdfc0001234 " is the same IFSC (E3)
  def self.normalised(value)
    value.to_s.gsub(/\s+/, "").upcase
  end

  # "4821" from "50100012344821"; nil for a blank value (E16, E23)
  def self.last4(value)
    normalised(value).last(4).presence
  end

  # Did the last save change a payout value (a first fill included)? Bank Verified was cleared in it.
  def bank_details_changed_in_last_save?
    @bank_details_changed_in_last_save == true
  end

  # Did the last save make a bank change (a payout value changed from a non-blank value)? Read by
  # InvestorKycAction#journey_hook to note "Bank details changed" when the journey moves back (E10).
  def bank_change_in_last_save?
    @bank_change_in_last_save == true
  end

  # ⑦ The newest change record, with its maker and confirmer (one query per page, memoised; E15 — a replaced change
  # is never the newest)
  def latest_bank_change
    return @latest_bank_change if defined?(@latest_bank_change)

    @latest_bank_change = persisted? ? bank_detail_changes.includes(:changed_by, :confirmed_by).order(id: :desc).first : nil
  end

  # ⑥ The change still waiting for a second person (nil when none, or once confirmed)
  def awaiting_bank_change
    change = latest_bank_change
    change if change&.awaiting?
  end

  # D5 — the maker: whoever the saving code named, else the person behind the request or job, else nobody (System)
  def bank_change_maker
    bank_change_actor || Current.user
  end

  # A fresh read of the KYC forgets the memoised change
  def reload(*)
    remove_instance_variable(:@latest_bank_change) if defined?(@latest_bank_change)
    super
  end

  private

  # ② before_save — decides, from the dirty values only, whether this save changes the bank details.
  def guard_bank_details
    # Fresh answer for every save of this object
    @bank_details_changed_in_last_save = false
    @bank_change_in_last_save = false
    @confirming_verify = false
    remove_instance_variable(:@marked_payout_keys) if defined?(@marked_payout_keys)

    changed = changed_payout_fields
    # H19, E63–E74 — the firm's marked payout custom fields (SWIFT, IBAN …) count like the account and IFSC; E64 —
    # unmarked custom fields never do. Masked by kind (D19).
    custom = new_record? ? [] : changed_payout_custom_fields
    # E2, E3, E4, E13, E70 — branch, bank name, account type, full name, or the same value re-typed: nothing more to
    # do unless this save verifies the KYC (H9, H10, E42, E45 — the Verify that confirms an awaiting change)
    return guard_verify if changed.empty? && custom.empty?

    # A new KYC: the tick (if any) was set by an approver on the new form — there is no older account it could
    # describe — so it is kept (Changed during the build C1). Bank change records start from the second save (E14).
    return true if new_record?

    # H1, H2, E1, E5–E8, E68 — the current payout details have not been checked: the flag clears in this same save,
    # even when the form still sends the old tick (E1)
    self.bank_verified = false
    # The old check result described the old account / IFSC. E74 — a change of custom fields only leaves the account
    # and IFSC as they were, so their check result stays (and no new penny drop is started for it)
    if changed.any?
      self.bank_verification_status = nil
      self.bank_verification_response = nil
    end
    @bank_details_changed_in_last_save = true

    # E14, E68 — first fill (every changed value was blank before): the flag clear above is all
    return true unless changed.any? { |field| attribute_in_database(field).present? } || custom.any? { |c| c["was_set"] }

    @bank_change_in_last_save = true
    # H5, E15, E16 — what changed, captured before the save overwrites it (masked when the record is written)
    @bank_change_details = changed.index_with { |field| [attribute_in_database(field), self[field]] }
    @bank_change_custom_fields = custom.map { |c| c.except("was_set") }
    # E9, E10 — a verified KYC (or one being verified in this same save) goes back to submitted-but-unverified,
    # exactly the state UnVerify leaves (InvestorKycsController#toggle_verified); sync_boolean_fields_from_status
    # then has nothing left to change
    unverify_for_bank_change if submission_status_in_database == "verified" || submission_status == "verified"
    true
  end

  # ③ after_save — H5, H6, E15–E18: replace the awaiting change (if any) and record this one; rolls back with the
  # KYC save when anything fails (X5)
  def record_bank_change
    @recorded_bank_change = nil
    # H9, H10, E42, E45 — a permitted Verify confirms the awaiting change by the verifier; X12 — only an awaiting row
    # moves, so a second Verify of the same change confirms nothing new
    if @confirming_verify
      @confirming_verify = false
      awaiting_bank_change&.confirm!(by: bank_change_maker, only_approver: bank_change_only_approver == true)
      remove_instance_variable(:@latest_bank_change) if defined?(@latest_bank_change)
      return true
    end
    return true unless @bank_change_in_last_save

    # E15 — a newer change overtakes the one nobody verified yet (kept, marked replaced; at most one row)
    bank_detail_changes.awaiting.find_each(&:replace!)
    @recorded_bank_change = bank_detail_changes.create!(bank_change_attributes)
    remove_instance_variable(:@latest_bank_change) if defined?(@latest_bank_change)
    true
  end

  # The record's columns: maker and side (D5), source, which fields, last 4 of the accounts, both IFSCs
  def bank_change_attributes
    details = @bank_change_details
    old_account, new_account = details["bank_account_number"]
    old_ifsc, new_ifsc = details["ifsc_code"]
    maker = bank_change_maker
    attrs = { entity_id:, changed_by: maker, changed_by_side: bank_change_side(maker),
              source: BANK_CHANGE_SOURCES.include?(bank_change_source) ? bank_change_source : "other",
              changed_fields: (details.keys + (@bank_change_custom_fields.any? ? ["custom_fields"] : [])).join(","),
              # D19 — the changed payout custom fields, by kind: a bank code in full, an account identifier last 4
              changed_custom_fields: @bank_change_custom_fields.presence }
    # E23 — the account number only as its last 4 digits; nil = blank (E16)
    if details.key?("bank_account_number")
      attrs[:old_account_last4] = BankDetailChangeGuard.last4(old_account)
      attrs[:new_account_last4] = BankDetailChangeGuard.last4(new_account)
    end
    # IFSC is a public branch code: in full
    if details.key?("ifsc_code")
      attrs[:old_ifsc] = old_ifsc.presence
      attrs[:new_ifsc] = new_ifsc.presence
    end
    attrs
  end

  # D5 — "system" with nobody behind the save (E18); "investor" for the magic link or a user of another entity (H6);
  # otherwise "fund" (a firm user, or CapHive support acting as one)
  def bank_change_side(maker)
    return "system" if maker.nil?
    return "investor" if maker.respond_to?(:signed_id_access?) && maker.signed_id_access?

    maker.entity_id == entity_id ? "fund" : "investor"
  end

  # ④ after_commit — H7, H8: queue the two emails; a failure here is reported, never raised into the save
  def notify_bank_change
    change = @recorded_bank_change
    @recorded_bank_change = nil
    return if change.nil?

    BankDetailChangeNotifyJob.perform_later(change.id)
  rescue StandardError => e
    ErrorReport.notify(e, source: "BankDetailChangeGuard#notify_bank_change", investor_kyc_id: id,
                          bank_detail_change_id: change&.id)
  end

  # ⑥ D4 — a save that verifies the KYC (no bank change in it) confirms the awaiting change, in after_save. The
  # policy decided who may verify; as a last line, the maker's own Verify never confirms their change unless the
  # policy said they are the only approver (E41) — the KYC then stays unverified.
  def guard_verify
    return true unless persisted? && becoming_verified?

    change = awaiting_bank_change
    return true if change.nil?

    if change.changed_by_id.present? && change.changed_by_id == bank_change_maker&.id && bank_change_only_approver != true
      unverify_for_bank_change
    else
      @confirming_verify = true
    end
    true
  end

  # This save moves the KYC to verified (the Verify button, bulk verify, an import row with Verified = Yes)
  def becoming_verified?
    submission_status == "verified" && submission_status_in_database != "verified"
  end

  # ⑨ The KYC form's marked payout keys ({ "swift_code" => { label:, kind: } }): no query unless json_fields changed
  # and the KYC has a form type; then one pluck over the old and new form type (memoised per save, and per import run)
  def marked_payout_keys
    return @marked_payout_keys if defined?(@marked_payout_keys)

    ids = [form_type_id_in_database, form_type_id].compact.uniq
    @marked_payout_keys = if !will_save_change_to_json_fields? || ids.empty?
                            {}
                          elsif bank_change_payout_keys_cache
                            bank_change_payout_keys_cache[ids] ||= FormCustomField.payout_keys_for(ids)
                          else
                            FormCustomField.payout_keys_for(ids)
                          end
  end

  # H19, E64, E69, E70, E72, E73 — each marked key whose normalised value this save changes, masked by kind. The
  # stored value comes from attribute_in_database (re-read from the column), so the extractor's in-place write
  # (json_fields[k] = v) is still compared with what was saved.
  def changed_payout_custom_fields
    keys = marked_payout_keys
    return [] if keys.empty?

    before = attribute_in_database(:json_fields) || {}
    after = json_fields || {}
    keys.filter_map do |key, info|
      old_value = before[key]
      new_value = after[key]
      next if BankDetailChangeGuard.normalised(old_value) == BankDetailChangeGuard.normalised(new_value)

      { "key" => key, "label" => info[:label], "kind" => info[:kind], "old" => masked_custom(old_value, info[:kind]),
        "new" => masked_custom(new_value, info[:kind]), "was_set" => old_value.present? }
    end
  end

  # D19 — a bank code (SWIFT) in full, an account identifier (IBAN) as its last 4; nil for blank
  def masked_custom(value, kind)
    return nil if value.blank?

    kind == "account" ? BankDetailChangeGuard.last4(value) : value.to_s.strip
  end

  # The payout columns whose normalised value this save changes (E3: a re-typed value is not a change)
  def changed_payout_fields
    PAYOUT_FIELDS.select do |field|
      will_save_change_to_attribute?(field) &&
        BankDetailChangeGuard.normalised(attribute_in_database(field)) != BankDetailChangeGuard.normalised(self[field])
    end
  end

  # D3 — the UnVerify state: submitted, not verified, nobody's sign-off
  def unverify_for_bank_change
    self.submission_status = "completed"
    self.verified = false
    self.verified_by_id = nil
  end
end
