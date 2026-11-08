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

When("the run's search verdict is taken over {int} complete indexes and {string}") do |ok, failure|
  grades = Array.new(ok) { |i| Dr::SearchIndexes.grade(index_name: "Index#{i}", es: 1, db: 1, exact: true) }
  grades << Dr::SearchIndexes::Grade.new(:fail, failure)
  @dr_grade = Dr::SearchIndexes.verdict(grades)
end

When("the run's search verdict is taken over {int} complete indexes") do |ok|
  @dr_grade = Dr::SearchIndexes.verdict(Array.new(ok) { |i| Dr::SearchIndexes.grade(index_name: "Index#{i}", es: 1, db: 1, exact: true) })
end

When("the {string} field of {string} is read for an AML report with custom name {string}") do |field, index_name, custom|
  # The field's value proc, applied to an unsaved record - no Elasticsearch needed
  report = AmlReport.new(custom_name: custom)
  definition = index_name.constantize.root.children.find { |f| f.name.to_s == field }
  @dr_indexed = definition.value.call(report)
end

Then("the indexed value is {string}") do |value|
  expect(@dr_indexed).to eq(value)
end

Given("an in-memory cache for the search rebuild") do
  # Tests run with :null_store; the rebuild record needs a cache that keeps what is written
  @dr_saved_cache = Rails.cache
  Rails.cache = ActiveSupport::Cache::MemoryStore.new
end

After do
  Rails.cache = @dr_saved_cache if @dr_saved_cache
end

Given("rebuilding any index succeeds") do
  # No Elasticsearch here: each index's rebuild is stubbed to a clean grade
  allow(Dr::SearchIndexes).to receive(:reindex_one) { |index, **_opts| Dr::SearchIndexes::Grade.new(:ok, "#{index.name}: 1 of 1") }
end

When("the search rebuild is queued for {string}") do |only|
  # ActiveJob runs inline in this suite, so the job runs as part of the enqueue
  Dr::SearchIndexes.enqueue_rebuild!(only.split(","))
end

Then("the search rebuild record is {string} with {int} of {int} indexes done and no problems") do |state, done, total|
  status = Dr::SearchIndexes.read_status
  expect(status).to include(state: state, done: done, total: total, problems: [])
end

Then("the search rebuild job runs on the {string} queue") do |queue|
  expect(SearchReindexJob.queue_name).to eq(queue)
end

When("a search rebuild record {string} with {int} of {int} done, queued {int} minutes ago, is graded") do |state, done, total, minutes|
  now = Time.utc(2026, 11, 8, 8, 0, 0)
  @dr_grade = Dr::SearchIndexes.grade_rebuild({ state: state, queued_at: (now - (minutes * 60)).iso8601, done: done, total: total, problems: [] }, now: now)
end

When("a search rebuild record {string} with {int} of {int} done, queued {int} hours ago, is graded") do |state, done, total, hours|
  now = Time.utc(2026, 11, 8, 8, 0, 0)
  @dr_grade = Dr::SearchIndexes.grade_rebuild({ state: state, queued_at: (now - (hours * 3600)).iso8601, done: done, total: total, problems: [] }, now: now)
end

When("a finished search rebuild of {int} with problem {string} is graded") do |total, problem|
  now = Time.utc(2026, 11, 8, 8, 0, 0)
  @dr_grade = Dr::SearchIndexes.grade_rebuild({ state: "finished", queued_at: (now - 600).iso8601, done: total, total: total, problems: [problem] }, now: now)
end

Then("there is no rebuild verdict, so each index is counted") do
  expect(@dr_grade).to be_nil
end
