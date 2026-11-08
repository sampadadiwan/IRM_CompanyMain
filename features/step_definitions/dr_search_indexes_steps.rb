# frozen_string_literal: true

# Steps for features/misc/dr_search_indexes.feature. Pure: index classes are discovered from the
# file tree and graded with given counts - nothing here talks to Elasticsearch or a server.

When("the search indexes a DR owns are discovered") do
  @dr_owned = Dr::SearchIndexes.indexes.map(&:name)
end

Then("{int} search indexes are owned by the DR") do |count|
  expect(@dr_owned.size).to eq(count)
end

Then("the owned search indexes include {string}, {string} and {string}") do |a, b, c|
  expect(@dr_owned).to include(a, b, c)
end

Then("{string} is not owned by the DR") do |name|
  expect(@dr_owned).not_to include(name)
end

When("an index is graded after reindex with import {string}, Elasticsearch {int} and MySQL {int}") do |import, es, db|
  @dr_grade = Dr::SearchIndexes.grade(index_name: "FolderIndex", es: es, db: db, imported: import == "clean", exact: true)
end

When("an index is graded in verification with Elasticsearch {int} and MySQL {int}") do |es, db|
  @dr_grade = Dr::SearchIndexes.grade(index_name: "FolderIndex", es: es, db: db, exact: false)
end

Then("the search grade is {string}") do |status|
  expect(@dr_grade.status).to eq(status.to_sym)
end

Then("the search grade is {string} mentioning {string}") do |status, text|
  expect(@dr_grade.status).to eq(status.to_sym)
  expect(@dr_grade.detail).to include(text)
end

Given("a new search index file {string} defining {string}") do |file, class_name|
  # A throwaway tree shaped like the app's: app/packs/<pack>/models/<name>_index.rb
  @dr_tree = Pathname.new(Dir.mktmpdir("dr_index_tree"))
  models = @dr_tree.join("app/packs/probe/models")
  FileUtils.mkdir_p(models)
  File.write(models.join(file), "# probe\n")
  # Define the class the file names, so discovery can resolve it like Zeitwerk would
  Object.const_set(class_name, Class.new(Chewy::Index)) unless Object.const_defined?(class_name)
end

When("the search indexes are discovered from that tree") do
  @dr_discovered = Dr::SearchIndexes.discover(@dr_tree).map(&:name)
ensure
  FileUtils.rm_rf(@dr_tree) if @dr_tree
end

Then("the discovered search indexes include {string}") do |name|
  expect(@dr_discovered).to include(name)
end

When("the MySQL scope of {string} is read") do |index_name|
  @dr_scope_sql = Dr::SearchIndexes.db_scope(index_name.constantize).to_sql
end

Then("that scope's SQL includes {string}") do |text|
  expect(@dr_scope_sql).to include(text)
end

Then("every excluded search index is a real index class with a reason") do
  discovered = Dr::SearchIndexes.discover.map(&:name)
  Dr::SearchIndexes::EXCLUDED.each do |name, reason|
    expect(discovered).to include(name)
    expect(reason.to_s.strip).not_to be_empty
  end
end

When("I read the database repair task's follow-up instructions") do
  @dr_fix_text = Rails.root.join("lib/tasks/dr_fix_db.rake").read
end

Then("they do not mention {string}") do |text|
  expect(@dr_fix_text).not_to include(text)
end

Then("they tell the operator to run {string}") do |text|
  expect(@dr_fix_text).to include(text)
end

Then("the Capistrano recovery tasks define {string}") do |task|
  expect(Rails.root.join("config/deploy.rb").read).to match(/task :#{task}\b/)
end

When("an unmaintained index is graded in verification with Elasticsearch {int} and MySQL {int}") do |es, db|
  @dr_grade = Dr::SearchIndexes.grade(index_name: "CapitalCallIndex", es: es, db: db, exact: false, maintained: false)
end

When("an unmaintained index is graded after reindex with Elasticsearch {int} and MySQL {int}") do |es, db|
  @dr_grade = Dr::SearchIndexes.grade(index_name: "CapitalCallIndex", es: es, db: db, exact: true, maintained: false)
end
