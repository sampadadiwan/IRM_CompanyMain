class DropInvestorKycSebiDatas < ActiveRecord::Migration[8.0]
  def change
    if table_exists?(:investor_kyc_sebi_datas)
      drop_table :investor_kyc_sebi_datas
    end
  end
end
