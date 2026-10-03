module InvestorKycConcern
  extend ActiveSupport::Concern

  def validate_pan_card
    validate_pan = (saved_change_to_PAN? && self.PAN.present?) || (saved_change_to_full_name? && full_name.present?) || (saved_change_to_birth_date? && birth_date.present?) || (self.PAN.present? && full_name.present? && birth_date.present? && pan_verification_response.blank?)

    return unless validate_pan

    if Rails.env.test?
      VerifyPanJob.perform_now(obj_class: self.class.to_s, obj_id: id)
    else
      VerifyPanJob.set(wait: rand(VerifyBankJob::DELAY_SECONDS).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  def validate_bank
    validate_bank = (saved_change_to_bank_account_number? && bank_account_number.present?) || (saved_change_to_ifsc_code? && ifsc_code.present?) || (saved_change_to_full_name? && full_name.present?) || (bank_account_number.present? && ifsc_code.present? && full_name.present? && bank_verification_response.blank?)

    return unless validate_bank

    if Rails.env.test?
      VerifyBankJob.perform_now(obj_class: self.class.to_s, obj_id: id)
    else
      VerifyBankJob.set(wait: rand(VerifyBankJob::DELAY_SECONDS).seconds).perform_later(obj_class: self.class.to_s, obj_id: id)
    end
  end

  def document_list
    if individual?
      docs = entity.entity_setting.individual_kyc_doc_list.split(",").map(&:strip) if entity.entity_setting.individual_kyc_doc_list.present?
    elsif entity.entity_setting.non_individual_kyc_doc_list.present?
      docs = entity.entity_setting.non_individual_kyc_doc_list.split(",").map(&:strip)
    end
    docs + ["Other"] if docs.present?
  end

  def profile_image
    documents.where(owner_tag: "Profile Image").last&.file
  end

  # Ovveride the include with_folder method
  def document_changed(document)
    started_at = Time.current
    grant_access_rights_to_investor(document)
    # Check if all the required docs have been uploaded
    local_docs_completed = docs_completed?
    update_column(:docs_completed, local_docs_completed) if local_docs_completed != docs_completed
    journey_document_changed(document, started_at)
  end

  # The KYC's journey after one of its documents is added, replaced or deleted: documents that were
  # validated are no longer the ones on file, so "Validate documents" goes back — but only once it had
  # passed (an upload while the investor is still filling the form is not a move back). Deleting a
  # document may also undo "Upload required documents". No-op without a journey; never raises.
  # Worked examples E5, E13 — openspec/changes/investor-kyc-journey/design.md#worked-examples
  def journey_document_changed(document, started_at)
    return unless respond_to?(:journey_progress!)
    # Documents CapHive generates for the KYC are not what was validated
    return if document.owner_tag == "Generated"

    # A deleted document leaves the remaining ones validated; a missing required one shows on
    # "Upload required documents" by itself
    # (Documents are soft-deleted, and destroyed? is not yet true inside the owner callback: ask the table)
    if document.destroyed? || !::Document.exists?(document.id)
      journey_undo_evaluate(note: "Document deleted", started_at:)
    else
      journey_invalidate(check_keys: "investor_kyc.validate_documents", reason: "Documents changed after validation",
                         only_if_passed: "investor_kyc.validate_documents")
      journey_undo_evaluate(note: "Documents changed after validation", started_at:)
    end
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Leading words the upload forms put in front of a document's name ("Upload Tax ID",
  # "Attach your CML") — stripped before comparing with the required names
  REQUIRED_DOC_NAME_PREFIX = /\A(upload|attach your|attach)\s+/i

  # Check if all the required docs have been uploaded
  def docs_completed?
    # The required_docs depend on the kyc_type
    required_docs = individual? ? entity.entity_setting.individual_kyc_doc_list : entity.entity_setting.non_individual_kyc_doc_list
    required_docs = required_docs.to_s.split(",").map(&:strip).compact_blank
    # No list configured means nothing can be "complete"; otherwise every required name must be matched
    # (other, unrequired docs may also be uploaded)
    required_docs.present? && missing_required_document_names(required_docs).empty?
  end

  # The names in required_names that no document on this KYC satisfies. A document satisfies a name when
  # its name or its owner_tag matches it after normalising - so "Upload Address Proof" counts as
  # "Address Proof", and "Upload Tax ID" (owner_tag "PAN", set by the form field's meta_data) counts as "PAN".
  # "Upload Correspondence Address Proof" does NOT count as "Address Proof": it is a different document.
  def missing_required_document_names(required_names)
    return [] if required_names.empty?

    # Every normalised name and tag on the KYC's documents, from one distinct query
    present = documents.distinct.pluck(:name, :owner_tag).flatten.filter_map { |v| normalize_required_doc_name(v).presence }.to_set
    # Keep the required names (as written in settings) that nothing matched
    required_names.reject { |name| present.include?(normalize_required_doc_name(name)) }
  end

  def docs_for_investor
    documents
      .where(owner_tag: "Generated", approved: true)
      .or(documents.where.not(owner_tag: "Generated"))
      .or(documents.where(owner_tag: nil))
      .not_template
  end

  private

  # "  Upload  Address Proof " -> "address proof": lowercase, collapse whitespace, drop an upload/attach prefix
  def normalize_required_doc_name(value)
    value.to_s.squish.downcase.sub(REQUIRED_DOC_NAME_PREFIX, "")
  end
end
