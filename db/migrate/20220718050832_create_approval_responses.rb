class CreateApprovalResponses < ActiveRecord::Migration[7.0]
  def change
    create_table :approval_responses do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :response_entity, null: false, foreign_key: {to_table: :entities}
      t.references :response_user, null: false, foreign_key: {to_table: :users}
      t.references :approval, null: false, foreign_key: true
      t.string :status, limit: 10

      t.timestamps
    end
  end
end
