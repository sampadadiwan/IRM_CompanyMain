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
      correspondence: %i[corr_line1 corr_line2 corr_line3 corr_city corr_pincode corr_dist corr_state corr_country],
      permanent: %i[perm_line1 perm_line2 perm_line3 perm_city perm_pincode perm_dist perm_state perm_country]
    }
  }.freeze

  def pan
    return "" if response.blank? || response["success"] == false

    if source == "ckyc"
      response.dig("download_response", "personal_details", "pan")
    else
      response.dig("pan_details", "pan_number")
    end
  end

  def full_name
    return "" if response.blank? || response["success"] == false

    if source == "ckyc"
      response.dig('download_response', 'personal_details', 'full_name')&.gsub(/\s+/, " ")&.titleize
    else
      response["name"]
    end
  end

  def email
    return "" if response.blank? || response["success"] == false

    if source == "ckyc"
      response.dig("download_response", "personal_details", "email")
    else
      response.dig("pan_details", "email_address")
    end
  end

  def phone
    return "" if response.blank? || response["success"] == false

    if source == "ckyc"
      "#{response.dig('download_response', 'personal_details', 'mob_code')&.strip}#{response.dig('download_response', 'personal_details', 'mob_no')&.strip}"
    else
      response.dig("pan_details", "mobile_number")
    end
  end

  def corr_address
    return "" if response.blank? || response["success"] == false

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
    corr_address = corr_address.compact_blank.join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end

  def perm_address
    return "" if response.blank? || response["success"] == false

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
    perm_address = perm_address.compact_blank.join(", ").gsub(/,(?=\s*\d{6}\b)/, " -")
  end

  def ckyc_number
    return "" if response.blank? || response["success"] == false || source != "ckyc"

    response.dig("download_response", "personal_details", "ckyc_no")
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
