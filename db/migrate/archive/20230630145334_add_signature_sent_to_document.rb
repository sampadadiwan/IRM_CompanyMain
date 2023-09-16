class AddSignatureSentToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :sent_for_esign, :boolean, default: false
  end
end
