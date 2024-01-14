class AddKycToExpressionOfInterest < ActiveRecord::Migration[7.1]
  def change
    add_reference :expression_of_interests, :investor_kyc, null: true, foreign_key: true
  end
end
