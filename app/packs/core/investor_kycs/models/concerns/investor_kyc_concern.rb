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
  # rubocop:disable Rails/SkipsModelValidations
  def document_changed(document)
    grant_access_rights_to_investor(document)
    # Check if all the required docs have been uploaded
    local_docs_completed = docs_completed?
    update_column(:docs_completed, local_docs_completed) if local_docs_completed != docs_completed
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Check if all the required docs have been uploaded
  def docs_completed?
    # The required_docs depend on the kyc_type
    required_docs = individual? ? entity.entity_setting.individual_kyc_doc_list : entity.entity_setting.non_individual_kyc_doc_list
    if required_docs.present?
      required_docs = Set.new(required_docs.split(",").map(&:strip))
      uploaded_docs = Set.new(documents.pluck(:name))
      # Sometimes other docs are also uploaded - so we check for subset
      required_docs.present? && required_docs.subset?(uploaded_docs)
    else
      false
    end
  end

  def docs_for_investor
    documents
      .where(owner_tag: "Generated", approved: true)
      .or(documents.where.not(owner_tag: "Generated"))
      .or(documents.where(owner_tag: nil))
      .not_template
      .order(:name)
  end
end
