class AddOwnerToValuation < ActiveRecord::Migration[7.0]
  def change
    add_reference :valuations, :owner, polymorphic: true, null: true
  end
end
