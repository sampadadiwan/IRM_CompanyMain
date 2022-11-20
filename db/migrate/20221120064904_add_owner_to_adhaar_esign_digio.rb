class AddOwnerToAdhaarEsignDigio < ActiveRecord::Migration[7.0]
  def change
    add_reference :adhaar_esigns, :owner, polymorphic: true, null: true
  end
end
