class KycData < ApplicationRecord
  include JsonTable
  belongs_to :investor_kyc
  belongs_to :entity

  ADDRESS_FIELDS = {
    kra: {
      correspondence: %i[correspondence_address1 correspondence_address2 correspondence_address3 correspondence_city correspondence_pincode correspondence_state correspondence_country],
      permanent: %i[permanent_address1 permanent_address2 permanent_address3 permanent_city permanent_pincode permanent_state permanent_country]
    },
    ckyc: {
      correspondence: %i[corr_address_line1 corr_address_line2 corr_address_line3 corr_address_city corr_address_pincode corr_address_dist corr_address_state corr_address_country],
      permanent: %i[perm_address_line1 perm_address_line2 perm_address_line3 perm_address_city perm_address_pincode perm_address_dist perm_address_state perm_address_country]
    }
  }.freeze

  def full_name
    return "" if response.blank?

    if source == "ckyc"
      response.dig('download_response', 'personal_details', 'full_name').gsub(/\s+/, " ").titleize
    else
      response["name"]
    end
  end

  def email
    return "" if response.blank?

    if source == "ckyc"
      response.dig("download_response", "personal_details", "email")
    else
      response.dig("pan_details", "email_address")
    end
  end

  def phone
    return "" if response.blank?

    if source == "ckyc"
      response.dig("download_response", "personal_details", "mobile_no")
    else
      response.dig("pan_details", "mobile_number")
    end
  end

  def corr_address
    return "" if response.blank?

    corr_address = []
    if source == "ckyc"
      ADDRESS_FIELDS[:ckyc][:correspondence].each do |field|
        corr_address << response.dig("download_response", "personal_details", field.to_s)
      end
    else
      ADDRESS_FIELDS[:kra][:correspondence].each do |field|
        corr_address << response.dig("pan_details", field.to_s)
      end
    end
    corr_address = corr_address.select(&:present?).join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end

  def perm_address
    return "" if response.blank?

    perm_address = []
    if source == "ckyc"
      ADDRESS_FIELDS[:ckyc][:permanent].each do |field|
        perm_address << response.dig("download_response", "personal_details", field.to_s)
      end
    else
      ADDRESS_FIELDS[:kra][:permanent].each do |field|
        perm_address << response.dig("pan_details", field.to_s)
      end
    end
    perm_address = perm_address.select(&:present?).join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end
end
