class AddOwnerToApproval < ActiveRecord::Migration[7.1]
  def change
    add_reference :approvals, :owner, polymorphic: true, null: true
  end
end
