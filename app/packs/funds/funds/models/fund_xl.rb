class FundXl
  include FormTypeHelper

  def dump_data(fund)
    file_path = "#{folder_path(fund)}/#{fund.name}.xlsx"

    Axlsx::Package.new do |xlsx_package|
      wb = xlsx_package.workbook

      form_type, custom_field_names, custom_headers = get_form_type("CapitalCommitment", entity_id: fund.entity_id)
      kyc_form_type, kyc_custom_field_names, kyc_custom_headers = get_form_type("InvestorKyc", entity_id: fund.entity_id)

      wb.add_worksheet(name: "CapitalCommitment") do |sheet|
        # Create the header row
        sheet.add_row(["Fund", "Investor", "Investing Entity", "Folio No", "Commitment Date", "Unit Type", "Percentage", "Folio Currency", "Committed (Folio Currency)", "Fund Currency", "Committed", "Called", "Collected", "Distributed", "Fund Close", "Virtual Bank Account"] + custom_headers + ["Investing Entity", "PAN", "Address", "Bank Account", "IFSC Code"] + kyc_custom_headers)

        # Create entries for each item
        fund.capital_commitments.includes(:investor_kyc).find_each do |cc|
          kyc = cc.investor_kyc
          custom_field_values = get_custom_values(cc, form_type, custom_field_names)
          kyc_custom_field_values = get_custom_values(kyc, kyc_form_type, kyc_custom_field_names)

          sheet.add_row [cc.fund.name, cc.investor_name, cc.investor_kyc&.full_name, cc.folio_id&.to_s, cc.commitment_date, cc.unit_type, cc.percentage, cc.folio_currency, cc.folio_committed_amount, cc.fund.currency, cc.committed_amount, cc.call_amount, cc.collected_amount, cc.distribution_amount, cc.fund_close, cc.virtual_bank_account] + custom_field_values + [kyc&.full_name, kyc&.PAN, kyc&.address, kyc&.bank_account_number, kyc&.ifsc_code] + kyc_custom_field_values
        end
      end

      form_type, custom_field_names, custom_headers = get_form_type("CapitalRemittance", entity_id: fund.entity_id)

      wb.add_worksheet(name: "CapitalRemittance") do |sheet|
        # Create the header row
        sheet.add_row(["Investor", "Fund", "Capital Call", "% Called", "Due Amount", "Folio Currency", "Committed Amount (Folio Currency)", "Call Amount (Folio Currency)", "Collected Amount (Folio Currency)", "Fund Currency", "Committed Amount", "Call Amount (Inclusive of Capital Fees)", "Capital Fees", "Other Fees", "Collected Amount", "Status", "Verified", "Payment Date", "Remittance Date"] + custom_headers)

        # Create entries for each item
        fund.capital_remittances.includes(:capital_call, :capital_commitment).find_each do |cc|
          verified = cc.verified ? "Yes" : "No"
          custom_field_values = get_custom_values(cc, form_type, custom_field_names)
          sheet.add_row [cc.investor_name, cc.fund.name, cc.capital_call.name, cc.capital_call.percentage_called, cc.due_amount, cc.capital_commitment.folio_currency, cc.folio_committed_amount, cc.folio_call_amount, cc.folio_collected_amount, cc.fund.currency, cc.committed_amount, cc.call_amount, cc.capital_fee, cc.other_fee, cc.collected_amount, cc.status, verified, cc.payment_date, cc.remittance_date] + custom_field_values
        end
      end

      xlsx_package.serialize(file_path)
    end
    file_path
  end

  def merge_data(fund, template_doc, user_id = nil)
    user_id ||= template_doc.user_id
    FileUtils.mkpath folder_path(fund)

    template_doc.file.download do |tempfile|
      template_path = tempfile.path

      # Dump the fund data out
      data_path = dump_data(fund)
      output_path = "#{folder_path(fund)}/#{fund.name}_merged.xlsx"

      # Invoke the rest api to merge the data
      if MergeXlApi.new.process(template_path, data_path, output_path, "FundXl")
        Rails.logger.debug "Merged data successfully"
        Document.create(entity_id: fund.entity_id, owner: fund, file: File.open(output_path), name: "#{template_doc.name}_#{Time.zone.now}.xlsx", orignal: true, user_id:, folder: fund.reports_folder)
      else
        Rails.logger.debug "Failed to merge data"
      end
    end

    # cleanup
    # FileUtils.rm(folder_path(fund))
  end

  def folder_path(fund)
    "/tmp/fund_xl/#{fund.entity_id}"
  end
end
