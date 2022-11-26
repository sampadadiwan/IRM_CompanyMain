class AddPropertiesToApproval < ActiveRecord::Migration[7.0]
  def change
    add_column :approvals, :properties, :text
    add_reference :approvals, :form_type, index: true

    add_column :capital_calls, :properties, :text
    add_reference :capital_calls, :form_type, index: true

    add_column :capital_commitments, :properties, :text
    add_reference :capital_commitments, :form_type, index: true

    add_column :capital_remittances, :properties, :text
    add_reference :capital_remittances, :form_type, index: true

    add_column :funds, :properties, :text
    add_reference :funds, :form_type, index: true
    
    add_column :investment_opportunities, :properties, :text

  end
end
