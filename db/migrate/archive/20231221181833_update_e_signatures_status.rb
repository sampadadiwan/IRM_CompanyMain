class UpdateESignaturesStatus < ActiveRecord::Migration[7.1]
  # update esignature statuses default to ""
  def change
    change_column :e_signatures, :status, :string, default: ""
    ESignature.where(status: nil).update_all(status: "")
  end
end
