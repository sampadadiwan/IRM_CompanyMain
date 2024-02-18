class AddJasonFieldToOptionPool < ActiveRecord::Migration[7.1]
  def change
    unless column_exists?(:option_pools, :json_fields)
      add_column :option_pools, :json_fields, :json
    end
    unless column_exists?(:excercises, :json_fields)
      add_column :excercises, :json_fields, :json
    end

      # Migrate old data from properties to json_fields
      existing = [OptionPool, Excercise]

      existing.each do |klass|
        puts "Migrating custom fields for #{klass.name}"
        next unless klass.column_names.include?("properties")
        klass.where.not(properties: {}).all.each do |m|
          m.update_column(:json_fields, m.properties)
        end
      end

      existing.each do |klass|
        klass.where(json_fields: nil).update_all(json_fields: {})
      end
  end
end
