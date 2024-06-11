class SetNilJsonFieldsToEmpty < ActiveRecord::Migration[7.1]
  def change
    DealInvestor.where(json_fields: nil).update_all(json_fields: {})
  end
end
