class GenerateIvestorKycSebiDatas < ActiveRecord::Migration[7.1]
  def change
    ActiveRecord::Base.transaction do
      InvestorKyc.all.each do |kyc|
        next if kyc.investor_kyc_sebi_data.present?
        Rails.logger.debug { "Creating InvestorSebiInfo for KYC #{kyc.id}" }
        InvestorKycSebiData.create!(investor_kyc_id: kyc.id, entity_id: kyc.entity_id)
      end
    end
  end
end
