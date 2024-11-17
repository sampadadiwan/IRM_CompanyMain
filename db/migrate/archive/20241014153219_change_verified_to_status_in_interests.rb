class ChangeVerifiedToStatusInInterests < ActiveRecord::Migration[7.1]
  def up
    # Add the new short_listed_status column with default 'pending'
    add_column :interests, :short_listed_status, :string, default: 'pending', null: false

    # Migrate existing data
    say_with_time "Migrating short_listed to short_listed_status" do
      # Use find_each to handle large datasets efficiently
      Interest.reset_column_information
      Interest.find_each do |interest|
        new_status = if interest.short_listed
                       'short_listed'
                     else
                       'pending' # Assuming false maps to 'pending'; adjust as needed
                     end
        interest.update_columns(short_listed_status: new_status)
      end
    end

    # Remove the old short_listed column
    remove_column :interests, :short_listed, :boolean
  end

  def down
    # Add the short_listed column back
    add_column :interests, :short_listed, :boolean, default: false, null: false

    # Migrate data back
    say_with_time "Reverting short_listed_status to short_listed" do
      Interest.reset_column_information
      Interest.find_each do |interest|
        short_listed = interest.short_listed_status == 'short_listed'
        interest.update_columns(short_listed: short_listed)
      end
    end

    # Remove the short_listed_status column
    remove_column :interests, :short_listed_status, :string
  end

end
