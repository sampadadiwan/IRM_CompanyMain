class AddAcceptedOnToUser < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :accepted_terms_on, :timestamp
  end
end
