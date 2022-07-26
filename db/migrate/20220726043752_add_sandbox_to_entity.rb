class AddSandboxToEntity < ActiveRecord::Migration[7.0]
  def change
    add_column :entities, :sandbox_emails, :text
    add_column :entities, :sandbox, :boolean, default: false
  end
end
