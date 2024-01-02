class CkycKraService
  def get_ckyc_data(investor_kyc)
    # search_ckyc_resp = KycVerify.new.search_ckyc(investor_kyc.entity.entity_setting.fi_code, investor_kyc.PAN)
    # if search_ckyc_resp.parsed_response["success"] == false
    #   Rails.logger.error("CKYC data not found for #{investor_kyc.PAN}. Error: #{search_ckyc_resp.parsed_response['error']}")
    #   KycData.create(entity: investor_kyc.entity, investor_kyc:, response: "", source: "ckyc")
    # else
    #   # dd-MM-yyyy format
    #   ckyc_response = KycVerify.new.download_ckyc_response(search_ckyc_resp.parsed_response, investor_kyc.entity.entity_setting.fi_code, investor_kyc.birth_date.strftime("%m-%d-%Y"))
    #   KycData.create(entity: investor_kyc.entity, investor_kyc:, response: ckyc_response, source: "ckyc")
    # end
    ckyc_response = KycVerify.new.download_ckyc_response("search_ckyc_resp.parsed_response", investor_kyc.entity.entity_setting.fi_code, investor_kyc.birth_date)
    KycData.create(entity: investor_kyc.entity, investor_kyc:, response: ckyc_response, source: "ckyc")
  end

  def get_kra_data(investor_kyc)
    kra_response = KycVerify.new.get_kra_pan_response(investor_kyc.PAN, investor_kyc.birth_date)
    KycData.create(entity: investor_kyc.entity, investor_kyc:, response: kra_response, source: "kra")
  end

  def get_ckyc_kra_datas(investor_kyc)
    get_ckyc_data(investor_kyc)
    get_kra_data(investor_kyc)
  end
end
