module InvestorKycConcern
  extend ActiveSupport::Concern

  def validate_pan_card
    if Rails.env.test?
      VerifyKycPanJob.perform_now(id) if (saved_change_to_PAN? && self.PAN.present?) || (saved_change_to_full_name? && full_name.present?) || (saved_change_to_birth_date? && birth_date.present?)
    elsif (saved_change_to_PAN? && self.PAN.present?) || (saved_change_to_full_name? && full_name.present?) || (saved_change_to_birth_date? && birth_date.present?)
      VerifyKycPanJob.set(wait: rand(300).seconds).perform_later(id)
    end
  end

  def validate_bank
    if Rails.env.test?
      VerifyKycBankJob.perform_now(id) if (saved_change_to_bank_account_number? && bank_account_number.present?) || (saved_change_to_ifsc_code? && ifsc_code.present?) || (saved_change_to_full_name? && full_name.present?)
    elsif (saved_change_to_bank_account_number? && bank_account_number.present?) || (saved_change_to_ifsc_code? && ifsc_code.present?) || (saved_change_to_full_name? && full_name.present?)
      VerifyKycBankJob.set(wait: rand(300).seconds).perform_later(id)
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
end
