class ChangeSendEmailInDocuments < ActiveRecord::Migration[7.0]
  def change
    change_column :documents, :send_email, :boolean, default: nil
  end
end
