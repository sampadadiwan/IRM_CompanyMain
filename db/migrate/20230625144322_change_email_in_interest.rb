class ChangeEmailInInterest < ActiveRecord::Migration[7.0]
  def change
    change_column :interests, :email, :string, length: 100
  end
end
