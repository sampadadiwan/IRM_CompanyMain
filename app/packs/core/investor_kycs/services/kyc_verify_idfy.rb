class KycVerifyIdfy
  def verify_pan_exists(pan)
    HTTParty.post(
      'https://eve.idfy.com/v3/tasks/sync/verify_with_source/ind_pan',
      headers: {
        "api-key" => ENV["IDFY_API_KEY"],
        "account-id" => ENV["IDFY_ACCOUNT_ID"]
      },
      body: {
        task_id: rand(5**5),
        group_id: "KYC_PAN",
        data:

            {
              id_number: pan
            }

        # avatar: File.open('/full/path/to/avatar.jpg')
      }
    )
  end

  def verify_pan_card(pan_card_url)
    HTTParty.post(
      'https://eve.idfy.com/v3/tasks/sync/extract/ind_pan',
      headers: {
        "api-key" => ENV["IDFY_API_KEY"],
        "account-id" => ENV["IDFY_ACCOUNT_ID"]
      },
      body: {
        task_id: rand(5**5),
        group_id: "KYC_PAN_EXTRACT",
        data:

            {
              document1: pan_card_url
            }

      }
    )
  end

  def verify_bank(account_number, ifsc)
    HTTParty.post(
      'https://eve.idfy.com/v3/tasks/sync/verify_with_source/validate_bank_account',
      headers: {
        "api-key" => ENV["IDFY_API_KEY"],
        "account-id" => ENV["IDFY_ACCOUNT_ID"]
      },
      body: {
        task_id: rand(5**5),
        group_id: "KYC_BANK_CHECK",
        data:

            {
              bank_account_no: account_number,
              bank_ifsc_code: ifsc
            }

      }
    )
  end
end
