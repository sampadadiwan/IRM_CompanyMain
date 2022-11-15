class AddFinalAgreementUserToInterest < ActiveRecord::Migration[7.0]
  def change
    add_reference :interests, :final_agreement_user, null: true, foreign_key: {to_table: :users}
  end
end
