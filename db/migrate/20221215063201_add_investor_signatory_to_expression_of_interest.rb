class AddInvestorSignatoryToExpressionOfInterest < ActiveRecord::Migration[7.0]
  def change
    add_reference :expression_of_interests, :investor_signatory, null: true, foreign_key: {to_table: :users}
  end
end
