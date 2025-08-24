class UpdateExistingRegulatoryCustomFieldsRegEnv < ActiveRecord::Migration[8.0]
  def change
    # blank so no data is automatically updated
    # Below method can be run as need in console
  end

  def update_existing_regulatory_custom_fields
    kyc_form_type_ids = FormType.where(name: ["IndividualKyc", "NonIndividualKyc"]).pluck(:id)
    fcfs = FormCustomField.where(form_type_id: kyc_form_type_ids, name: ["investor_category", "investor_sub_category"])
    puts "KYC custom fields - Updating #{fcfs.count} custom fields ids -\n #{fcfs.pluck(:id)}"
    fcfs.each do |fcf|
      name = "sebi_#{fcf.name}"
      label = InvestorKyc::REPORTING_FIELDS[:sebi][name.to_sym][:label]
      fcf.update_columns(name: name, reg_env: "SEBI", read_only: true, label: label, internal: true)
    end

    instrument_form_type_ids = FormType.where(name: "InvestmentInstrument").pluck(:id)
    names = [:type_of_investee_company, :type_of_security, :details_of_security, :isin, :sebi_registration_number, :is_associate, :is_managed_or_sponsored_by_aif, :sector, :offshore_investment]
    fcfs = FormCustomField.where(form_type_id: instrument_form_type_ids, name: names)
    puts "Investment Instrument custom fields - Updating #{fcfs.count} custom fields ids -\n #{fcfs.pluck(:id)}"
    fcfs.each do |fcf|
      name = fcf.name == "sebi_registration_number" ? fcf.name : "sebi_#{fcf.name}"
      label = InvestmentInstrument::REPORTING_FIELDS[:sebi][name.to_sym][:label]
      fcf.update_columns(name: name, reg_env: "SEBI", read_only: true, label: label, internal: true)
    end

    #############Update existing KYC and Investment Instrument custom fields###########################
    InvestorKyc.where(form_type_id: kyc_form_type_ids).each do |kyc|
      if kyc.json_fields.key?("investor_category")
        puts "Updating KYC - #{kyc.id}"
        kyc.json_fields["sebi_investor_category"] = kyc.json_fields.delete("investor_category")
      end
      if kyc.json_fields.key?("investor_sub_category")
        kyc.json_fields["sebi_investor_sub_category"] = kyc.json_fields.delete("investor_sub_category")
      end
      kyc.save(validate: false)
    end

    InvestmentInstrument.where(form_type_id: instrument_form_type_ids).each do |instrument|
      if instrument.json_fields.key?("type_of_investee_company")
        puts "Updating Investment Instrument - #{instrument.id}"
        instrument.json_fields["sebi_type_of_investee_company"] = instrument.json_fields.delete("type_of_investee_company")
      end
      if instrument.json_fields.key?("type_of_security")
        instrument.json_fields["sebi_type_of_security"] = instrument.json_fields.delete("type_of_security")
      end
      if instrument.json_fields.key?("details_of_security")
        instrument.json_fields["sebi_details_of_security"] = instrument.json_fields.delete("details_of_security")
      end
      if instrument.json_fields.key?("isin")
        instrument.json_fields["sebi_isin"] = instrument.json_fields.delete("isin")
      end
      if instrument.json_fields.key?("is_associate")
        instrument.json_fields["sebi_is_associate"] = instrument.json_fields.delete("is_associate")
      end
      if instrument.json_fields.key?("is_managed_or_sponsored_by_aif")
        instrument.json_fields["sebi_is_managed_or_sponsored_by_aif"] = instrument.json_fields.delete("is_managed_or_sponsored_by_aif")
      end
      if instrument.json_fields.key?("sector")
        instrument.json_fields["sebi_sector"] = instrument.json_fields.delete("sector")
      end
      if instrument.json_fields.key?("offshore_investment")
        instrument.json_fields["sebi_offshore_investment"] = instrument.json_fields.delete("offshore_investment")
      end
      instrument.save(validate: false)
    end
  end

  def update_already_present_sebi_keys
    entity_ids_bad = [6051, 69]
    ftids = FormType.where(name: ["IndividualKyc", "NonIndividualKyc"], entity_id: entity_ids_bad).pluck(:id)
    reg_env = "SEBI"
    reg_env_key = :sebi
   
      FormCustomField.where(form_type_id: ftids, name: ["sebi_investor_category", "sebi_investor_sub_category"]).each do |fcf|
        fcf.update_columns(reg_env: reg_env, read_only: true, internal: true, field_type: "Select",
                            label: InvestorKyc::REPORTING_FIELDS[reg_env_key][fcf.name.to_sym][:label],
                            meta_data: InvestorKyc::REPORTING_FIELDS[reg_env_key][fcf.name.to_sym][:meta_data],
                            js_events: InvestorKyc::REPORTING_FIELDS[reg_env_key][fcf.name.to_sym][:js_events]
        )
    end
  end
end
