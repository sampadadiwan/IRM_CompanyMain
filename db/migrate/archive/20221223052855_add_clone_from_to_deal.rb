class AddCloneFromToDeal < ActiveRecord::Migration[7.0]
  def change
    add_reference :deals, :clone_from, null: true, foreign_key: {to_table: :deals}
  end
end
