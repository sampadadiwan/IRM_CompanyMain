class RemoveDocShareIndex < ActiveRecord::Migration[8.0]
  def change
    remove_index :doc_shares, :email, unique: true
  end
end
