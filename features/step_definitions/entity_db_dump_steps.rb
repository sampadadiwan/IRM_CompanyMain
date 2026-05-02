include ActiveJob::TestHelper

Given('the entity has database dumps enabled') do
  @user.entity.entity_setting.update!(db_dumps_enable: true, db_dumps_email_enabled: true)
end

Given('I am at the entity page for {string}') do |entity_name|
  entity = Entity.find_by(name: entity_name)
  visit entity_path(entity)
end

When('I confirm the dialog {string}') do |lable|
  # In Playwright, we might need to handle the dialog
  # But for now, let's see if it works without explicit handling or if we need to stub it
  click_on lable
end

Then('a database dump job should be enqueued for {string}') do |entity_name|
  entity = Entity.find_by(name: entity_name)
  expect(EntityDbDumpJob).to have_been_enqueued.with(entity_id: entity.id)
end

Given('the user has the tag {string}') do |tag|
  @user.tag_list = tag
  @user.save!
end

When('the database dump job runs for {string}') do |entity_name|
  entity = Entity.find_by(name: entity_name)

  # DEBUG
  puts "DEBUG: Entity: #{entity.name} (ID: #{entity.id})"
  puts "DEBUG: Entity Setting db_dumps_email_enabled: #{entity.entity_setting.db_dumps_email_enabled}"
  puts "DEBUG: User: #{@user.email} (ID: #{@user.id})"
  puts "DEBUG: User Entity ID: #{@user.entity_id}"
  puts "DEBUG: User active: #{@user.active}"
  puts "DEBUG: User tag_list: #{@user.tag_list}"
  puts "DEBUG: Is user in entity.employees? #{entity.employees.include?(@user)}"

  # Stub the system call to avoid running the actual shell script
  allow_any_instance_of(EntityDbDumpJob).to receive(:system).and_return(true)

  # Mock Time.zone.now for predictable filenames
  fixed_time = Time.zone.now.change(usec: 0)
  allow(Time.zone).to receive(:now).and_return(fixed_time)

  timestamp = fixed_time.strftime('%Y%m%d_%H%M%S')
  filename = "db_dump_#{entity.id}_#{timestamp}.sqlite3"
  filepath = Rails.root.join("tmp", filename).to_s

  # Run the job
  File.delete(filepath) if File.exist?(filepath)
  require "sqlite3"
  db = SQLite3::Database.new(filepath)
  db.execute("CREATE TABLE dump(content TEXT)")
  db.execute("INSERT INTO dump VALUES ('test dump')")
  db.close
  puts "DEBUG: Starting EntityDbDumpJob.perform_now for entity #{entity.id}"
  perform_enqueued_jobs do
    EntityDbDumpJob.perform_now(entity_id: entity.id)
  end
  puts "DEBUG: Finished EntityDbDumpJob.perform_now"

  # Cleanup the dummy file
  File.delete(filepath) if File.exist?(filepath)
end

Then('a document named {string} should be created for {string} in the {string} folder') do |doc_name, entity_name, folder_name|
  entity = Entity.find_by(name: entity_name)
  folder = entity.folders.find_by(name: folder_name)
  expect(folder).to be_present
  document = folder.documents.where("name LIKE ?", "#{doc_name}%").first
  expect(document).to be_present
  expect(document.entity).to eq(entity)
end

Then('the user should receive an email with {string} in the subject') do |subject|
  open_email(@user.email)
  expect(current_email).to be_present
  expect(current_email.subject).to include(subject)
end

Given('a database dump document exists for {string} created 10 days ago') do |entity_name|
  entity = Entity.find_by(name: entity_name)
  temp_folder = entity.root_folder.children.find_or_create_by!(name: "Temp", entity: entity, folder_type: :regular)

  # Create a dummy file for the document
  filepath = "/home/thimmaiah/work/IRM/tmp/old_dump.sqlite3"
  File.delete(filepath) if File.exist?(filepath)
  require "sqlite3"
  db = SQLite3::Database.new(filepath)
  db.execute("CREATE TABLE dump(content TEXT)")
  db.execute("INSERT INTO dump VALUES ('old dump')")
  db.close

  @old_doc = Document.new(
    name: "Old DB Dump",
    entity: entity,
    folder: temp_folder,
    user: @user,
    owner: entity,
    owner_tag: "DB Dump"
  )
  File.open(filepath) do |file|
    @old_doc.file = file
    @old_doc.save!
  end
  @old_doc.update_columns(created_at: 20.days.ago)

  File.delete(filepath) if File.exist?(filepath)
end

Given('the entity retention period is set to 7 days') do
  @user.entity.entity_setting.update!(db_dumps_retention_period: 7)
end

Then('the old database dump document should be deleted') do
  puts "DEBUG: Checking if old doc #{@old_doc.id} exists. Created at: #{@old_doc.created_at}"
  expect(Document.exists?(@old_doc.id)).to be_falsey
end
