class AddReportingFieldsToFund < ActiveRecord::Migration[7.0]
  def change
    add_column :funds, :registration_number, :string, limit: 20
    add_column :funds, :category, :string, limit: 15
    add_column :funds, :sub_category, :string, limit: 40
    add_column :funds, :sponsor_name, :string, limit: 100
    add_column :funds, :manager_name, :string, limit: 100
    add_column :funds, :trustee_name, :string, limit: 100
    add_column :funds, :contact_name, :string, limit: 100
    add_column :funds, :contact_email, :string, limit: 100
  end
end
