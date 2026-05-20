class AddAsOfToDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :documents, :as_of, :date
  end
end
