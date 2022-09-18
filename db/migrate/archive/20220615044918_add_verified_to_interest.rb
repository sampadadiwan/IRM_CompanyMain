class AddVerifiedToInterest < ActiveRecord::Migration[7.0]
  def change
    add_column :interests, :verified, :boolean, default: false
    add_column :interests, :comments, :text
  end
end
