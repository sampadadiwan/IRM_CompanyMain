class AddDocsUploadedCheckToOffer < ActiveRecord::Migration[7.0]
  def change
    add_column :offers, :docs_uploaded_check, :text
  end
end
