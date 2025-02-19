class AddInvestorPresentationEmailToEntitySetting < ActiveRecord::Migration[7.1]
  def change
    # add_column :entity_settings, :investor_presentations_email, :string, limit: 100
    # add_column :entity_settings, :domain, :string

    # Entity.all.each do |entity|
    #   entity.entity_setting.update(investor_presentations_email: entity.primary_email)
    #   entity.entity_setting.update(domain: entity.primary_email.split("@").last) if entity.primary_email.present?
    # end
  end
end
