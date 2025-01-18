class MigrateSebiDataToKycs < ActiveRecord::Migration[7.2]
  def change
    updated = []
    errs = []
    InvestorKycSebiData.includes(:investor_kyc).where("investor_kyc_sebi_datas.investor_category IS NOT NULL OR investor_kyc_sebi_datas.investor_sub_category IS NOT NULL").find_each do |kyc_sebi_data|
      kyc = kyc_sebi_data.investor_kyc
      if kyc_sebi_data.investor_category.present?
        kyc.json_fields["investor_category"] = kyc_sebi_data.investor_category
      end
      if kyc_sebi_data.investor_sub_category.present?
        kyc.json_fields["investor_sub_category"] = kyc_sebi_data.investor_sub_category
      end
      res = kyc.save(validate: false)
      if res
        updated << kyc.id
      else
        errs << kyc.id
      end
    end
    Rails.logger.info "Updated: #{updated.size}, Errors: #{errs.size}"
    Rails.logger.info "Updated: #{updated}, Errors: #{errs}"

    entity_updated = []
    entity_errs = []
    entity_ids = InvestorKycSebiData.includes(:investor_kyc).where("investor_kyc_sebi_datas.investor_category IS NOT NULL OR investor_kyc_sebi_datas.investor_sub_category IS NOT NULL").pluck(:entity_id).uniq
    entity_ids.each do |entity_id|
      entity = Entity.find(entity_id)
      result = AddSebiFields.call(entity: entity)
      if result
        entity_updated << entity.id
        Rails.logger.info "Added SEBI custom fields for entity: #{entity.id}"
      else
        entity_errs << [entity.id, entity.errors.full_messages]
        Rails.logger.error "Error adding SEBI custom fields for entity: #{entity.id}"
      end
    end
    Rails.logger.info "Updated: #{entity_updated.size}, Errors: #{entity_errs.size}"
    Rails.logger.info "Updated: #{entity_updated}, Errors: #{entity_errs}"
  end
end
