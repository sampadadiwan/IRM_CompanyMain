class CreateFundSnapshots < ActiveRecord::Migration[7.0]
  
  TABLES = %w[funds capital_commitments portfolio_investments aggregate_portfolio_investments]

  def down
    TABLES.each do |table|
      # Drop the table
      drop_table "#{table.singularize}_snapshots"
    end
  end

  def up

    TABLES.each do |table|
      # Fetch the columns from the existing 'funds' table
      table_columns = ActiveRecord::Base.connection.columns(table)

      create_table "#{table.singularize}_snapshots", id: false, primary_keys: [:id, :snapshot_date] do |t|
        # Ensure its not auto-incrementing, as it will be copied over from the funds table
        t.bigint :id, null: false

        table_columns.each do |col|
          # Skip the old table's primary key if you want a new one
          # or handle it differently
          next if ['id', 'created_at', 'updated_at'].include?(col.name)

          # Determine the type recognized by Active Record
          # (e.g. :integer, :string, :decimal, :boolean)
          column_type = col.type

          # Build out a list of options for the new column
          column_options = {
            limit:      col.limit,
            precision:  col.precision,
            scale:      col.scale,
            default:    col.default,
            null:       col.null
          }

          # Define the column in the new table
          t.send(column_type, col.name, **column_options)
        end

        # If you want timestamps automatically for fund_snapshots
        # (independent of the funds' created_at/updated_at columns):
        t.timestamps      
        # Add a snapshot_date defaulting to the current date for mysql
        t.date :snapshot_date
      end

      # Add the indexes to the new table
      add_index "#{table.singularize}_snapshots", [:id, :snapshot_date], name: "index_#{table}_on_id_and_snapshot_date"
      add_index "#{table.singularize}_snapshots", [:snapshot_date], name: "index_#{table}_on_snapshot_date"
      add_index "#{table.singularize}_snapshots", [:id], name: "index_#{table}_on_id"
    end
  end
end
