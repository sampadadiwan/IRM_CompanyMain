class AddRequiredDocsToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :individual_kyc_doc_list, :string
    add_column :entity_settings, :non_individual_kyc_doc_list, :string
    Entity.all.each do |e|
      e.entity_setting.individual_kyc_doc_list = e.kyc_doc_list
      e.entity_setting.save
    end
    remove_column :entities, :kyc_doc_list, :string
  end
end
