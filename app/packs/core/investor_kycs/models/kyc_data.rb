class KycData < ApplicationRecord
  include JsonTable

  belongs_to :investor_kyc
  belongs_to :entity

  ADDRESS_FIELDS = {
    kra: {
      correspondence: %i[address_line1 address_line2 city pincode state country],
      permanent: %i[address_line1 address_line2 city pincode state country]
    },
    ckyc: {
      correspondence: %i[corr_address_line1 corr_address_line2 corr_address_line3 corr_address_city corr_address_pincode corr_address_dist corr_address_state corr_address_country],
      permanent: %i[perm_address_line1 perm_address_line2 perm_address_line3 perm_address_city perm_address_pincode perm_address_dist perm_address_state perm_address_country]
    }
  }.freeze

  enum :source, { kra: "kra", ckyc: "ckyc" }

  validates :source, :PAN, presence: true
  validates :birth_date, presence: true, if: :kra?
  validates :phone, presence: true, if: :ckyc?

  validates :phone,
            format: { with: /\A\d{10}\z/, message: "must be exactly 10 digits and contain only numbers" },
            if: :ckyc?
  validates :PAN, format: { with: /\A[A-Z]{5}[0-9]{4}[A-Z]\z/, message: "must be a valid PAN number" }
  validates :PAN, uniqueness: { scope: %i[source investor_kyc_id], message: "should be unique for the same source and KYC" }

  def can_resend_otp?
    return false if otp_resend_count.to_i >= 3
    return true if otp_sent_at.nil?

    Time.current - otp_sent_at >= 90.seconds
  end

  def remaining_otp_attempts
    3 - otp_resend_count.to_i
  end

  def response_pan
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    if source == "ckyc"
      response.dig("download_response", "personal_details", "pan")
    else
      response.dig("personal_information", "pan_number")
    end
  end

  def full_name
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    if source == "ckyc"
      response.dig('download_response', 'personal_details', 'full_name')&.gsub(/\s+/, " ")&.titleize
    else
      response.dig("personal_information", "name")&.gsub(/\s+/, " ")&.titleize
    end
  end

  def email
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    if source == "ckyc"
      response.dig("download_response", "personal_details", "email")
    else
      response.dig("contact_information", "email_address")
    end
  end

  def phone_from_response
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    if source == "ckyc"
      "#{response.dig('download_response', 'personal_details', 'mob_code')&.strip}#{response.dig('download_response', 'personal_details', 'mobile_no')&.strip}"
    else
      response.dig("contact_information", "mobile_number")
    end
  end

  def corr_address
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    corr_address = []
    if source == "ckyc"
      ADDRESS_FIELDS[:ckyc][:correspondence].each do |field|
        corr_address << response.dig("download_response", "personal_details", field.to_s)
      end
    else
      ADDRESS_FIELDS[:kra][:correspondence].each do |field|
        corr_address << response.dig("contact_information", "correspondence_address", field.to_s)
      end
    end
    corr_address = corr_address.compact_blank.join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end

  def perm_address
    return nil if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    perm_address = []
    if source == "ckyc"
      ADDRESS_FIELDS[:ckyc][:permanent].each do |field|
        perm_address << response.dig("download_response", "personal_details", field.to_s)
      end
    else
      ADDRESS_FIELDS[:kra][:permanent].each do |field|
        perm_address << response.dig("contact_information", "permanent_address", field.to_s)
      end
    end
    perm_address = perm_address.compact_blank.join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end

  def ckyc_number
    return nil if response.blank? || (response["success"] == false && ckyc?) || kra?

    response.dig("download_response", "personal_details", "ckyc_reference_id")
  end

  # eg - Validated
  def kra_status
    return nil if ckyc? || response.blank? || !kra_success

    response.dig("kyc_information", "status")
  end

  # eg - 007 - for validated
  def kra_status_code
    return nil if ckyc? || response.blank? || !kra_success

    response.dig("kyc_information", "status_code")
  end

  # eg - KYC details have been successfully verified. Customer can start investing - for code 007
  def kra_status_description
    return nil if ckyc? || response.blank? || !kra_success

    response.dig("kyc_information", "status_description")
  end

  # does pan match with the one in investor_kyc
  def pan_match
    return false if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    investor_kyc.PAN == self.PAN
  end

  # does phone match with the one in investor_kyc
  def birth_date_match
    return false if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    investor_kyc.birth_date == birth_date
  end

  # does name match with the one in investor_kyc
  def full_name_match
    return false if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    investor_kyc.full_name == full_name
  end

  # does address match with the one in investor_kyc
  def address_match
    return false if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    investor_kyc.address == perm_address && investor_kyc.corr_address == corr_address
  end

  # does correspondence address match with the one in investor_kyc
  def corr_address_match
    return false if response.blank? || (response["success"] == false && ckyc?) || (kra? && !kra_success)

    investor_kyc.corr_address == corr_address
  end

  def kra_success
    return false if response.blank? || ckyc?

    response.dig("kyc_information", "status_description")&.include?("KYC details have been successfully verified. Customer can start investing")
  end

  def get_json_table
    if source == "ckyc"
      Json2table.get_html_table(response['download_response']&.except("images"), JsonTable::TABLE_OPTIONS)
    else
      Json2table.get_html_table(response, JsonTable::TABLE_OPTIONS)
    end
  end

  def get_image_data
    if source == "ckyc" && response.present?
      response.dig('download_response', 'images')
    else
      []
    end
  end
end
