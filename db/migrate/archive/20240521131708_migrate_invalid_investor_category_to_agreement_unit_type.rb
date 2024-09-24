class MigrateInvalidInvestorCategoryToAgreementUnitType < ActiveRecord::Migration[7.1]
  def change

    if Rails.env.production?
     sebi_data_ids = [3946, 3947, 3948, 3949, 3950, 3951, 3952, 3953, 3954, 3955, 3956, 3957, 3971, 3972, 3973, 3974, 3975, 3976, 3977, 3978, 3979, 3980, 3981]

      ActiveRecord::Base.transaction do
        InvestorKycSebiData.where(id: sebi_data_ids).each do |sebi_data|
          Rails.logger.debug { "Updating InvestorKycSebiData #{sebi_data.id} 's kyc  agreement_unit_type to #{sebi_data.investor_category}" }
          sebi_data.investor_kyc.update_columns(agreement_unit_type: sebi_data.investor_category)
          sebi_data.update_columns(investor_category: nil)
        end
      end
    end

  end
end
