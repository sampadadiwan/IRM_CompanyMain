class AddCompletedToInterest < ActiveRecord::Migration[7.1]
  def change
    add_column :interests, :completed, :boolean, default: false
    add_column :offers, :completed, :boolean, default: false
  end
end
