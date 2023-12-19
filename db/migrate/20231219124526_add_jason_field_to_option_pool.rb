class AddJasonFieldToOptionPool < ActiveRecord::Migration[7.1]
  def change
      add_column :option_pools, :json_fields, :json
      add_column :excercises, :json_fields, :json

      # Migrate old data from properties to json_fields
      existing = [OptionPool, Excercise]
  
      existing.each do |klass|
        puts "Migrating custom fields for #{klass.name}"
        klass.where.not(properties: {}).all.each do |m|
          m.update_column(:json_fields, m.properties)
        end
      end
  
      existing.each do |klass|
        klass.where(json_fields: nil).update_all(json_fields: {})
      end
  end
end
