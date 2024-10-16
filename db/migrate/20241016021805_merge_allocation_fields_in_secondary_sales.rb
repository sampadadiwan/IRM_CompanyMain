# db/migrate/20240101123456_merge_allocation_fields_in_secondary_sales.rb

class MergeAllocationFieldsInSecondarySales < ActiveRecord::Migration[7.1]

  def up
    # 1. Add the new columns
    add_column :secondary_sales, :allocation_quantity, :decimal, precision: 10, scale: 2, default: 0
    add_column :secondary_sales, :allocation_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    # 2. Migrate data from old columns to new columns
    # Assuming offer_allocation_quantity == interest_allocation_quantity
    # and allocation_offer_amount_cents == allocation_interest_amount_cents
    SecondarySale.reset_column_information

    SecondarySale.find_each do |secondary_sale|
      # Assign allocation_quantity
      secondary_sale.allocation_quantity = secondary_sale.offer_allocation_quantity

      # Assign allocation_amount_cents
      secondary_sale.allocation_amount_cents = secondary_sale.allocation_offer_amount_cents

      # Save the changes without running validations
      secondary_sale.save(validate: false)
    end

    # 3. Remove the old columns
    remove_column :secondary_sales, :offer_allocation_quantity, :integer
    remove_column :secondary_sales, :interest_allocation_quantity, :integer
    remove_column :secondary_sales, :allocation_offer_amount_cents, :integer
    remove_column :secondary_sales, :allocation_interest_amount_cents, :integer

    # 4. Add NOT NULL constraints and default values if necessary
    # (Optional based on your application's requirements)
    # change_column_null :secondary_sales, :allocation_quantity, false
    # change_column_null :secondary_sales, :allocation_amount_cents, false

    # 5. Add indexes if the old columns had them and are necessary for new columns
    # (Optional based on your application's requirements)
    # add_index :secondary_sales, :allocation_quantity
    # add_index :secondary_sales, :allocation_amount_cents
  end

  def down
    # 1. Add the old columns back
    add_column :secondary_sales, :offer_allocation_quantity, :decimal, precision: 10, scale: 2, default: 0
    add_column :secondary_sales, :interest_allocation_quantity, :decimal, precision: 20, scale: 2, default: 0
    add_column :secondary_sales, :allocation_offer_amount_cents, :decimal, precision: 10, scale: 2, default: 0
    add_column :secondary_sales, :allocation_interest_amount_cents, :decimal, precision: 20, scale: 2, default: 0

    # 2. Migrate data from new columns back to old columns
    SecondarySale.reset_column_information

    SecondarySale.find_each do |secondary_sale|
      # Assign offer_allocation_quantity and interest_allocation_quantity
      secondary_sale.offer_allocation_quantity = secondary_sale.allocation_quantity
      secondary_sale.interest_allocation_quantity = secondary_sale.allocation_quantity

      # Assign allocation_offer_amount_cents and allocation_interest_amount_cents
      secondary_sale.allocation_offer_amount_cents = secondary_sale.allocation_amount_cents
      secondary_sale.allocation_interest_amount_cents = secondary_sale.allocation_amount_cents

      # Save the changes without running validations
      secondary_sale.save(validate: false)
    end

    # 3. Remove the new columns
    remove_column :secondary_sales, :allocation_quantity, :integer
    remove_column :secondary_sales, :allocation_amount_cents, :integer

    # 4. Remove NOT NULL constraints if they were added
    # (Optional based on your application's requirements)
    change_column_null :secondary_sales, :offer_allocation_quantity, true
    change_column_null :secondary_sales, :interest_allocation_quantity, true
    change_column_null :secondary_sales, :allocation_offer_amount_cents, true
    change_column_null :secondary_sales, :allocation_interest_amount_cents, true

    # 5. Remove indexes if they were added
    # (Optional based on your application's requirements)
    # remove_index :secondary_sales, :allocation_quantity
    # remove_index :secondary_sales, :allocation_amount_cents
  end
end
