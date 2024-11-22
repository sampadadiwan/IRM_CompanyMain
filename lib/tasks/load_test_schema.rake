namespace :db do
    namespace :test do
      Rake::Task[:load_schema].clear # Clear the original task
  
      desc "Loads test schema from schema_test.rb"
      task load_schema: :environment do
        schema_test_path = Rails.root.join('db', 'schema_test.rb')
        if File.exist?(schema_test_path)
          puts "Loading test schema from schema_test.rb"
          load schema_test_path
        else
          puts "schema_test.rb not found. Falling back to schema.rb"
          Rake::Task["db:schema:load"].invoke
        end
      end
    end
end
  