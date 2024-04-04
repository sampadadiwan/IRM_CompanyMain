# rubocop:disable Metrics/ClassLength
class InfoOnInvestorsJob
  include CurrencyHelper

  REPORT_NAME = "InfoOnInvestors".freeze
  TABLE_1_OFFSET = 4
  TABLE_2_OFFSET = 3
  TABLE_3_OFFSET = 3
  SHEET_2_NAME = "Funds raised (INR)".freeze
  SHEET_3_NAME = "Commitment received (INR)".freeze

  def hash_tree
    Hash.new do |hash, key|
      hash[key] = hash_tree
    end
  end

  def generate_report(fund_id, start_date, end_date)
    Rails.logger.debug { "Table 5: Generating Report for #{fund_id}, #{start_date}, #{end_date} " }

    @fund = Fund.includes(capital_commitments: { investor_kyc: :investor_kyc_sebi_data }).find(fund_id)

    @fund_report = FundReport.find_or_initialize_by(name: REPORT_NAME, name_of_scheme: @fund.name, fund: @fund, entity_id: @fund.entity_id, start_date:, end_date:)

    data = hash_tree

    kyc_sebi_datas = InvestorKycSebiData.where(investor_kyc_id: @fund.capital_commitments.where("commitment_date <= ?", end_date).select(:investor_kyc_id))

    # Table 1 data
    data.merge!(report_table_1_data(kyc_sebi_datas, @fund))
    # Table 2 data
    data.merge!(report_table_2_data(kyc_sebi_datas, end_date, @fund))
    # Table 3 data
    data.merge!(report_table_3_data(kyc_sebi_datas, end_date, @fund))

    ######### Save the report
    @fund_report.data = data
    @fund_report.save!
  end

  def generate_excel_report(fund_id, _start_date, end_date, excel, single: false)
    fund = Fund.find(fund_id)
    sheet1 = excel.worksheet(FundReportJob::REPORT_TO_SHEET[REPORT_NAME])
    sheet2 = excel.worksheet(SHEET_2_NAME)
    sheet3 = excel.worksheet(SHEET_3_NAME)

    sheet1[3, 24] = "Difference"

    funds = fund.entity.funds
    funds = funds.where(id: fund_id) if single

    funds.each_with_index do |scheme, index|
      kyc_sebi_datas = InvestorKycSebiData.where(investor_kyc_id: scheme.capital_commitments.where("commitment_date <= ?", end_date).select(:investor_kyc_id))
      sr_no = index + 1
      scheme_name = scheme.name
      Rails.logger.debug { "InfoOnInvestors for #{scheme_name}" }
      table_1_row_data = get_table_1_row_data(scheme, kyc_sebi_datas, sr_no)
      table_2_row_data = get_table_2_row_data(scheme, kyc_sebi_datas, end_date, sr_no)
      table_3_row_data = get_table_3_row_data(scheme, kyc_sebi_datas, end_date, sr_no)

      table_1_index = index + TABLE_1_OFFSET
      table_2_index = index + TABLE_2_OFFSET
      table_3_index = index + TABLE_3_OFFSET

      if index.zero?
        sheet1.update_row(table_1_index, *table_1_row_data)
        sheet2.update_row(table_2_index, *table_2_row_data)
        sheet3.update_row(table_3_index, *table_3_row_data)
      else
        sheet1.insert_row(table_1_index, table_1_row_data)
        sheet2.insert_row(table_2_index, table_2_row_data)
        sheet3.insert_row(table_3_index, table_3_row_data)
      end
    end
    excel
  end

  def report_table_1_data(kyc_sebi_datas, fund)
    data = hash_tree
    data["Name of the Scheme"]["Value"] = fund.name
    data["T1_Sponsor"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Sponsor").count
    data["T1_Manager"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Manager").count
    data["T1_Directors/Partners/Employees of Sponsor"]["Value"] = kyc_sebi_datas.where(investor_sub_category: ["Directors/Partners/Employees of Sponsor"]).count
    data["T1_Directors/Partners/Employees of Manager"]["Value"] = kyc_sebi_datas.where(investor_sub_category: ["Directors/Partners/Employees of Manager"]).count
    data["T1_Employee Benefit Trust of Manager"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Employee Benefit Trust of Manager").count
    data["T1_Banks"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Banks").count
    data["T1_NBFCs"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "NBFCs").count
    data["T1_Insurance Companies"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Insurance Companies").count
    data["T1_Pension Funds"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Pension Funds").count
    data["T1_Provident Funds"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Provident Funds").count
    data["T1_AIFs"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "AIFs").count
    data["T1_Other Corporates"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Other Corporates").count
    data["T1_Resident Individuals"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Resident Individuals").count
    data["T1_Non-Corporate (other than Trusts)"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Non-Corporate (other than Trusts)").count
    data["T1_Trusts"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Trusts").count
    data["T1_FPIs"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "FPIs").count
    data["T1_FVCIs"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "FVCIs").count
    data["T1_NRIs"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "NRIs").count
    data["T1_Foreign Others"]["Value"] = kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").count

    data["T1_Domestic Developmental Agencies / Government Agencies"]["Value"] = kyc_sebi_datas.where(investor_sub_category: "Domestic Developmental Agencies/Government Agencies").count
    data["T1_Other Others"]["Value"] = kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").count
    data["T1_Total"]["Value"] = kyc_sebi_datas.count
    data
  end

  # rubocop:disable Metrics/MethodLength
  def report_table_2_data(kyc_sebi_datas, end_date, fund)
    data = hash_tree
    data["T2_Sponsor"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Sponsor", end_date, :amount, fund.id)
    data["T2_Manager"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Manager", end_date, :amount, fund.id)
    data["T2_Directors/Partners/Employees of Sponsor"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Sponsor", end_date, :amount, fund.id)
    data["T2_Directors/Partners/Employees of Manager"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Manager", end_date, :amount, fund.id)
    data["T2_Employee Benefit Trust of Manager"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Employee Benefit Trust of Manager", end_date, :amount, fund.id)
    data["T2_Banks"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Banks", end_date, :amount, fund.id)
    data["T2_NBFCs"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "NBFCs", end_date, :amount, fund.id)
    data["T2_Insurance Companies"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Insurance Companies", end_date, :amount, fund.id)
    data["T2_Pension Funds"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Pension Funds", end_date, :amount, fund.id)
    data["T2_Provident Funds"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Provident Funds", end_date, :amount, fund.id)
    data["T2_AIFs"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "AIFs", end_date, :amount, fund.id)
    data["T2_Other Corporates"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Other Corporates", end_date, :amount, fund.id)
    data["T2_Resident Individuals"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Resident Individuals", end_date, :amount, fund.id)
    data["T2_Non-Corporate (other than Trusts)"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Non-Corporate (other than Trusts)", end_date, :amount, fund.id)
    data["T2_Trusts"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Trusts", end_date, :amount, fund.id)
    data["T2_FPIs"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "FPIs", end_date, :amount, fund.id)
    data["T2_FVCIs"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "FVCIs", end_date, :amount, fund.id)
    data["T2_NRIs"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "NRIs", end_date, :amount, fund.id)
    sum = 0
    kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").find_each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    data["T2_Foreign Others"]["Value"] = money_to_currency(Money.new(sum))
    data["T2_Domestic Developmental Agencies / Government Agencies"]["Value"] = t2_calculate_sum(kyc_sebi_datas, "Domestic Developmental Agencies/Government Agencies", end_date, :amount, fund.id)

    sum = 0
    kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").find_each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    data["T2_Other Others"]["Value"] = money_to_currency(Money.new(sum))
    sum = 0
    kyc_sebi_datas.each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    data["T2_Total"]["Value"] = money_to_currency(Money.new(sum))
    data
  end

  def report_table_3_data(kyc_sebi_datas, end_date, fund)
    data = hash_tree
    data["T3_Sponsor"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Sponsor", end_date, :committed_amount, fund.id)
    data["T3_Manager"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Manager", end_date, :committed_amount, fund.id)
    data["T3_Directors/Partners/Employees of Sponsor"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Sponsor", end_date, :committed_amount, fund.id)
    data["T3_Directors/Partners/Employees of Manager"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Manager", end_date, :committed_amount, fund.id)
    data["T3_Employee Benefit Trust of Manager"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Employee Benefit Trust of Manager", end_date, :committed_amount, fund.id)
    data["T3_Banks"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Banks", end_date, :committed_amount, fund.id)
    data["T3_NBFCs"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "NBFCs", end_date, :committed_amount, fund.id)
    data["T3_Insurance Companies"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Insurance Companies", end_date, :committed_amount, fund.id)
    data["T3_Pension Funds"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Pension Funds", end_date, :committed_amount, fund.id)
    data["T3_Provident Funds"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Provident Funds", end_date, :committed_amount, fund.id)
    data["T3_AIFs"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "AIFs", end_date, :committed_amount, fund.id)
    data["T3_Other Corporates"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Other Corporates", end_date, :committed_amount, fund.id)
    data["T3_Resident Individuals"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Resident Individuals", end_date, :committed_amount, fund.id)
    data["T3_Non-Corporate (other than Trusts)"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Non-Corporate (other than Trusts)", end_date, :committed_amount, fund.id)
    data["T3_Trusts"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Trusts", end_date, :committed_amount, fund.id)
    data["T3_FPIs"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "FPIs", end_date, :committed_amount, fund.id)
    data["T3_FVCIs"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "FVCIs", end_date, :committed_amount, fund.id)
    data["T3_NRIs"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "NRIs", end_date, :committed_amount, fund.id)
    data["T3_Foreign Others"]["Value"] = money_to_currency(Money.new(kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end))
    data["T3_Domestic Developmental Agencies / Government Agencies"]["Value"] = t3_calculate_sum(kyc_sebi_datas, "Domestic Developmental Agencies/Government Agencies", end_date, :committed_amount, fund.id)

    data["T3_Other Others"]["Value"] = money_to_currency(Money.new(kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end))
    data["T3_Total"]["Value"] = money_to_currency(Money.new(kyc_sebi_datas.sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: fund.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end))
    data
  end

  def t2_calculate_sum(kyc_sebi_datas, sub_cat, end_date, sum_method, fund_id, mtc: true)
    sum = 0
    kyc_sebi_datas.where(investor_sub_category: sub_cat).find_each do |investor_kyc_sebi_data|
      # go to remittance payment level and sum
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id:).where("commitment_date <= ?", end_date).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&sum_method)
          sum += amt if amt.present?
        end
      end
    end
    mtc ? money_to_currency(Money.new(sum)) : Money.new(sum)
  end

  def t3_calculate_sum(kyc_sebi_datas, sub_cat, end_date, sum_method, fund_id, mtc: true)
    money = Money.new(kyc_sebi_datas.where(investor_sub_category: sub_cat).sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id:).where("commitment_date <= ?", end_date).sum(&sum_method)
    end)
    mtc ? money_to_currency(money) : money
  end

  def get_table_1_row_data(scheme, kyc_sebi_datas, sr_no)
    sponsor_count = kyc_sebi_datas.where(investor_sub_category: "Sponsor").count
    manager_count = kyc_sebi_datas.where(investor_sub_category: "Manager").count
    personnel_of_sponsor_count = kyc_sebi_datas.where(investor_sub_category: ["Directors/Partners/Employees of Sponsor"]).count
    personnel_of_manager_count = kyc_sebi_datas.where(investor_sub_category: ["Directors/Partners/Employees of Manager"]).count
    employee_benefit_trust_of_manager_count = kyc_sebi_datas.where(investor_sub_category: "Employee Benefit Trust of Manager").count
    bank_count = kyc_sebi_datas.where(investor_sub_category: "Banks").count
    nbfc_count = kyc_sebi_datas.where(investor_sub_category: "NBFCs").count
    insurance_companies_count = kyc_sebi_datas.where(investor_sub_category: "Insurance Companies").count
    pension_funds_count = kyc_sebi_datas.where(investor_sub_category: "Pension Funds").count
    provident_funds_count = kyc_sebi_datas.where(investor_sub_category: "Provident Funds").count
    aifs_count = kyc_sebi_datas.where(investor_sub_category: "AIFs").count
    other_corporates_count = kyc_sebi_datas.where(investor_sub_category: "Other Corporates").count
    resident_individuals_count = kyc_sebi_datas.where(investor_sub_category: "Resident Individuals").count
    non_corporate_other_than_trusts_count = kyc_sebi_datas.where(investor_sub_category: "Non-Corporate (other than Trusts)").count
    trusts_count = kyc_sebi_datas.where(investor_sub_category: "Trusts").count
    fpi_count = kyc_sebi_datas.where(investor_sub_category: "FPIs").count
    fvci_count = kyc_sebi_datas.where(investor_sub_category: "FVCIs").count
    nri_count = kyc_sebi_datas.where(investor_sub_category: "NRIs").count
    foreign_others_count = kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").count
    domestic_developmental_agencies_government_agencies_count = kyc_sebi_datas.where(investor_sub_category: "Domestic Developmental Agencies/Government Agencies").count
    other_others_count = kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").count
    total_count = sponsor_count + manager_count + personnel_of_sponsor_count + personnel_of_manager_count + employee_benefit_trust_of_manager_count + bank_count + nbfc_count + insurance_companies_count + pension_funds_count + provident_funds_count + aifs_count + other_corporates_count + resident_individuals_count + non_corporate_other_than_trusts_count + trusts_count + fpi_count + fvci_count + nri_count + foreign_others_count + domestic_developmental_agencies_government_agencies_count + other_others_count
    difference = kyc_sebi_datas.count - total_count

    [sr_no, scheme.name, sponsor_count, manager_count, personnel_of_sponsor_count, personnel_of_manager_count, employee_benefit_trust_of_manager_count, bank_count, nbfc_count, insurance_companies_count, pension_funds_count, provident_funds_count, aifs_count, other_corporates_count, resident_individuals_count, non_corporate_other_than_trusts_count, trusts_count, fpi_count, fvci_count, nri_count, foreign_others_count, domestic_developmental_agencies_government_agencies_count, other_others_count, total_count, difference]
  end

  # in this table sum the capital commitment's collected amount of the investor of filtered investor_kyc_sebi_data
  def get_table_2_row_data(scheme, kyc_sebi_datas, end_date, sr_no)
    sponsor_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Sponsor", end_date, :amount, scheme.id, mtc: false).amount.to_d
    manager_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Manager", end_date, :amount, scheme.id, mtc: false).amount.to_d
    personnel_of_sponsor_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Sponsor", end_date, :amount, scheme.id, mtc: false).amount.to_d
    personnel_of_manager_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Manager", end_date, :amount, scheme.id, mtc: false).amount.to_d
    employee_benefit_trust_of_manager_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Employee Benefit Trust of Manager", end_date, :amount, scheme.id, mtc: false).amount.to_d
    bank_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Banks", end_date, :amount, scheme.id, mtc: false).amount.to_d
    nbfc_coll_amt = t2_calculate_sum(kyc_sebi_datas, "NBFCs", end_date, :amount, scheme.id, mtc: false).amount.to_d
    insurance_companies_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Insurance Companies", end_date, :amount, scheme.id, mtc: false).amount.to_d
    pension_funds_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Pension Funds", end_date, :amount, scheme.id, mtc: false).amount.to_d
    provident_funds_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Provident Funds", end_date, :amount, scheme.id, mtc: false).amount.to_d
    aifs_coll_amt = t2_calculate_sum(kyc_sebi_datas, "AIFs", end_date, :amount, scheme.id, mtc: false).amount.to_d
    other_corporates_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Other Corporates", end_date, :amount, scheme.id, mtc: false).amount.to_d
    resident_individuals_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Resident Individuals", end_date, :amount, scheme.id, mtc: false).amount.to_d
    non_corporate_other_than_trusts_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Non-Corporate (other than Trusts)", end_date, :amount, scheme.id, mtc: false).amount.to_d
    trusts_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Trusts", end_date, :amount, scheme.id, mtc: false).amount.to_d
    fpi_coll_amt = t2_calculate_sum(kyc_sebi_datas, "FPIs", end_date, :amount, scheme.id, mtc: false).amount.to_d
    fvci_coll_amt = t2_calculate_sum(kyc_sebi_datas, "FVCIs", end_date, :amount, scheme.id, mtc: false).amount.to_d
    nri_coll_amt = t2_calculate_sum(kyc_sebi_datas, "NRIs", end_date, :amount, scheme.id, mtc: false).amount.to_d
    sum = 0
    kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").find_each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    foreign_others_coll_amt = Money.new(sum).amount.to_d
    domestic_developmental_agencies_government_agencies_coll_amt = t2_calculate_sum(kyc_sebi_datas, "Domestic Developmental Agencies/Government Agencies", end_date, :amount, scheme.id, mtc: false).amount.to_d
    sum = 0
    kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").find_each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    other_others_coll_amt = Money.new(sum).amount.to_d
    sum = 0
    kyc_sebi_datas.each do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).find_each do |cc|
        cc.capital_remittances.where("remittance_date <= ?", end_date).find_each do |cr|
          amt = cr.capital_remittance_payments.where("payment_date <= ?", end_date).sum(&:amount)
          sum += amt if amt.present?
        end
      end
    end
    total_coll_amt = Money.new(sum).amount.to_d

    [sr_no, scheme.name, sponsor_coll_amt, manager_coll_amt, personnel_of_sponsor_coll_amt, personnel_of_manager_coll_amt, employee_benefit_trust_of_manager_coll_amt, bank_coll_amt, nbfc_coll_amt, insurance_companies_coll_amt, pension_funds_coll_amt, provident_funds_coll_amt, aifs_coll_amt, other_corporates_coll_amt, resident_individuals_coll_amt, non_corporate_other_than_trusts_coll_amt, trusts_coll_amt, fpi_coll_amt, fvci_coll_amt, nri_coll_amt, foreign_others_coll_amt, domestic_developmental_agencies_government_agencies_coll_amt, other_others_coll_amt, total_coll_amt]
  end

  # in this table sum the capital commitment's committed amount of the investor of filtered investor_kyc_sebi_data
  def get_table_3_row_data(scheme, kyc_sebi_datas, end_date, sr_no)
    sponsor_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Sponsor", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    manager_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Manager", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    personnel_of_sponsor_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Sponsor", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    personnel_of_manager_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Directors/Partners/Employees of Manager", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    employee_benefit_trust_of_manager_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Employee Benefit Trust of Manager", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    bank_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Banks", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    nbfc_comm_amt = t3_calculate_sum(kyc_sebi_datas, "NBFCs", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    insurance_companies_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Insurance Companies", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    pension_funds_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Pension Funds", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    provident_funds_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Provident Funds", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    aifs_comm_amt = t3_calculate_sum(kyc_sebi_datas, "AIFs", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    other_corporates_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Other Corporates", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    resident_individuals_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Resident Individuals", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    non_corporate_other_than_trusts_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Non-Corporate (other than Trusts)", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    trusts_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Trusts", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    fpi_comm_amt = t3_calculate_sum(kyc_sebi_datas, "FPIs", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    fvci_comm_amt = t3_calculate_sum(kyc_sebi_datas, "FVCIs", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    nri_comm_amt = t3_calculate_sum(kyc_sebi_datas, "NRIs", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d
    foreign_others_comm_amt = Money.new(kyc_sebi_datas.where(investor_category: "Foreign", investor_sub_category: "Foreign Others").sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end).amount.to_d
    domestic_developmental_agencies_government_agencies_comm_amt = t3_calculate_sum(kyc_sebi_datas, "Domestic Developmental Agencies/Government Agencies", end_date, :committed_amount, scheme.id, mtc: false).amount.to_d

    other_others_comm_amt = Money.new(kyc_sebi_datas.where(investor_category: "Other", investor_sub_category: "Others").sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end).amount.to_d

    total_comm_amt = Money.new(kyc_sebi_datas.sum do |investor_kyc_sebi_data|
      investor_kyc_sebi_data.investor_kyc.capital_commitments.where(fund_id: scheme.id).where("commitment_date <= ?", end_date).sum(&:committed_amount)
    end).amount.to_d

    [sr_no, scheme.name, sponsor_comm_amt, manager_comm_amt, personnel_of_sponsor_comm_amt, personnel_of_manager_comm_amt, employee_benefit_trust_of_manager_comm_amt, bank_comm_amt, nbfc_comm_amt, insurance_companies_comm_amt, pension_funds_comm_amt, provident_funds_comm_amt, aifs_comm_amt, other_corporates_comm_amt, resident_individuals_comm_amt, non_corporate_other_than_trusts_comm_amt, trusts_comm_amt, fpi_comm_amt, fvci_comm_amt, nri_comm_amt, foreign_others_comm_amt, domestic_developmental_agencies_government_agencies_comm_amt, other_others_comm_amt, total_comm_amt]
  end
end
# rubocop:enable Metrics/MethodLength
# rubocop:enable Metrics/ClassLength
