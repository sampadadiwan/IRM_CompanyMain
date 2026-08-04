class AddOwnerToNotes < ActiveRecord::Migration[8.1]
  def change
    add_reference :notes, :owner, polymorphic: true, null: true
  end
end
