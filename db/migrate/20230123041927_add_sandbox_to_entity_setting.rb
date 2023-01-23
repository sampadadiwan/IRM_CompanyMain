class AddSandboxToEntitySetting < ActiveRecord::Migration[7.0]
  def change
    add_column :entity_settings, :sandbox, :boolean
    add_column :entity_settings, :sandbox_emails, :string
    add_column :entity_settings, :from_email, :string, limit: 100

    Entity.all.each do |e|
      e.entity_setting.update(sandbox: e.sandbox, sandbox_emails: e.sandbox_emails, from_email: e.from_email)
    end

    remove_column :entities, :sandbox
    remove_column :entities, :sandbox_emails
    remove_column :entities, :from_email

  end
end
