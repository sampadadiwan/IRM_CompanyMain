class AddFormTypeToApprovalResponse < ActiveRecord::Migration[7.1]
  def change
    add_reference :approval_responses, :form_type, null: true, foreign_key: true
    add_column :approval_responses, :json_fields, :json, null: true
    add_column :approval_responses, :folio_id, :string, null: true, limit:20, default: "n/a"
    ApprovalResponse.update_all(json_fields: {})
  end
end
