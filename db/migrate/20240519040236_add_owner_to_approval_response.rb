class AddOwnerToApprovalResponse < ActiveRecord::Migration[7.1]
  def change
    remove_column :approval_responses, :folio_id
    add_reference :approval_responses, :owner, polymorphic: true, null: true
  end
end
