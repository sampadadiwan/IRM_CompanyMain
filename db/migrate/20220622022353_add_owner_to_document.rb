class AddOwnerToDocument < ActiveRecord::Migration[7.0]
  def change
    add_reference :documents, :owner, polymorphic: true, null: true
  end
end
