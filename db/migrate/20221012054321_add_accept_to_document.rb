class AddAcceptToDocument < ActiveRecord::Migration[7.0]
  def change
    add_column :documents, :signed_by_accept, :boolean, default: false
  end
end
