# Job to automate the generation of per-entity SQLite database dumps.
require 'fileutils'
# It iterates through all entities that have the `db_dumps_enable` setting turned on,
# generates a SQLite file using a shell script, uploads it as a Document,
# notifies relevant users, and cleans up old dumps based on a retention period.
class EntityDbDumpJob < ApplicationJob
  queue_as :low

  # Performs the database dump for a specific entity or all eligible entities.
  # @param entity_id [Integer, nil] The ID of the entity to dump. If nil, all eligible entities are processed.
  # @param user_id [Integer, nil] The ID of the user who triggered the dump (for notifications).
  # @param adhoc [Boolean] Whether this is an adhoc request from the UI. If true, skips are notified to the user.
  def perform(entity_id: nil, user_id: nil, adhoc: false)
    @user_id = user_id

    # Wrap in Chewy strategy to handle index updates for Document creation/deletion
    Chewy.strategy(:atomic) do
      if entity_id.present?
        entity = Entity.find(entity_id)
        if entity.entity_setting.db_dumps_enable
          setting = entity.entity_setting
          # Even for manual/adhoc runs, we respect the frequency settings.
          # This prevents redundant dumps if the user clicks the button multiple times.
          # If the frequency is set to 'adhoc', we always allow the manual trigger.
          if adhoc || should_run_today?(entity)
            Rails.logger.info "Starting DB dump for entity #{entity.id}"
            process_entity_dump(entity)
          else
            msg = "DB dump skipped for entity #{entity.id} as it was already performed for this period."
            Rails.logger.info msg
            # Only notify the user if they explicitly requested this via the UI (adhoc).
            send_notification(msg, @user_id, "info") if adhoc
          end
        else
          Rails.logger.warn "DB dump requested for entity #{entity.id} but feature is disabled in settings"
        end
      else
        # Find all entities where the DB dump feature is enabled in their settings.
        Rails.logger.info "Starting automated DB dumps"
        Entity.joins(:entity_setting).where(entity_settings: { db_dumps_enable: true }).find_each do |entity|
          # Automated runs (e.g. from DailyMorningJob) always respect frequency.
          if should_run_today?(entity)
            process_entity_dump(entity)
          else
            Rails.logger.info "Skipping DB dump for entity #{entity.id} based on frequency settings"
          end
        rescue StandardError => e
          # Log errors per entity so one failure doesn't stop the entire batch.
          Rails.logger.error "Error dumping DB for entity #{entity.id}: #{e.message}"
          ExceptionNotifier.notify_exception(e, data: { entity_id: entity.id })
        end
      end
    end
  end

  private

  # Checks if a DB dump should be performed today based on the entity's frequency settings.
  def should_run_today?(entity)
    setting = entity.entity_setting
    return false if setting.db_dumps_frequency.adhoc?

    case setting.db_dumps_frequency.to_sym
    when :daily
      !entity.documents.where(owner_tag: "DB Dump").exists?(created_at: Time.zone.now.all_day)
    when :weekly
      !entity.documents.where(owner_tag: "DB Dump").exists?(created_at: Time.zone.now.all_week)
    when :monthly
      !entity.documents.where(owner_tag: "DB Dump").exists?(created_at: Time.zone.now.all_month)
    when :interval
      interval = setting.db_dumps_interval || 1
      !entity.documents.where(owner_tag: "DB Dump").exists?(["created_at > ?", (interval - 1).days.ago.beginning_of_day])
    when :custom_days
      days = setting.db_dumps_custom_days.to_s.split(",").map { |d| d.strip.downcase }
      today = Time.zone.now.strftime("%A").downcase
      days.include?(today) && !entity.documents.where(owner_tag: "DB Dump").exists?(created_at: Time.zone.now.all_day)
    else
      true
    end
  end

  # Orchestrates the dump process for a single entity.
  def process_entity_dump(entity)
    send_notification("Starting DB dump for entity #{entity.name} (ID: #{entity.id})", @user_id, "info")
    setting = entity.entity_setting
    timestamp = Time.zone.now.strftime('%Y%m%d_%H%M%S')
    filename = "db_dump_#{entity.id}_#{timestamp}.sqlite3"
    filepath = Rails.root.join("tmp", filename).to_s

    Rails.logger.info "Generating DB dump for entity #{entity.id} at #{filepath}"

    # Prepare environment variables for the shell script.
    # We pull the current database configuration to ensure the script connects to the right source.
    db_config = ActiveRecord::Base.connection_db_config.configuration_hash
    env = {
      'ENTITY_ID' => entity.id.to_s,
      'SQLITE_DB' => filepath
    }

    if Rails.env.test? && db_config[:adapter] == 'sqlite3'
      env['ADAPTER'] = 'sqlite3'
      env['SOURCE_SQLITE_DB'] = db_config[:database]
    else
      env.merge!({
        'MYSQL_HOST' => db_config[:host] || '127.0.0.1',
        'MYSQL_PORT' => (db_config[:port] || 3306).to_s,
        'MYSQL_USER' => db_config[:username],
        'MYSQL_PASS' => db_config[:password].to_s, # Ensure it's a string, even if nil
        'MYSQL_DB' => db_config[:database]
      })
    end

    script_path = Rails.root.join("script/load_entity_sqlite3.sh").to_s

    # Execute the shell script to perform the actual data extraction and SQLite conversion.
    Rails.logger.info "Executing script: #{script_path}"
    raise "Failed to generate sqlite dump for entity #{entity.id}. Check logs for script errors." unless system(env, "bash #{script_path}")

    raise "SQLite file was not created at #{filepath} even though script returned success" unless File.exist?(filepath)

    msg = "DB dump generated successfully. Size: #{File.size(filepath)} bytes"
    Rails.logger.info msg
    send_notification(msg, @user_id)

    # Ensure we have a "Temp" folder to store these dumps.
    temp_folder = find_or_create_temp_folder(entity)
    Rails.logger.info "Using folder: #{temp_folder.name} (ID: #{temp_folder.id})"

    # Determine a user to 'own' the document creation.
    # We prefer a Company Admin, then any employee, then a support user as a fallback.
    user = entity.employees.company_admins.first || entity.employees.first || User.support_users.first

    # Initialize a new Document record for the SQLite file.
    document = Document.new(
      name: "DB Dump #{Time.zone.now.strftime('%Y-%m-%d %H:%M')}",
      entity: entity,
      folder: temp_folder,
      user: user,
      owner: entity,
      orignal: true,
      owner_tag: "DB Dump" # Used for identification during cleanup.
    )

    # Attach the generated file using Shrine.
    File.open(filepath) do |file|
      document.file = file
      document.save!
    end

    Rails.logger.info "Document created: #{document.id}"
    doc_url = Rails.application.routes.url_helpers.document_path(document)
    docs_url = Rails.application.routes.url_helpers.documents_path(folder_id: temp_folder.id)
    send_notification("DB dump document created: <a href='#{doc_url}'>#{document.name}</a>. View all <a href='#{docs_url}'>Dumps</a>.", @user_id)

    # Send out email notifications if enabled for this entity.
    if setting.db_dumps_email_enabled
      Rails.logger.info "Sending email notifications"
      notify_users(document)
    end

    # Remove older dumps to stay within the retention limit.
    cleanup_old_dumps(entity, temp_folder, setting.db_dumps_retention_period)

    # Clean up the local temporary file.
    FileUtils.rm_f(filepath)
    Rails.logger.info "Finished processing DB dump for entity #{entity.id}"
  end

  # Finds or creates a "Temp" folder under the entity's root folder.
  def find_or_create_temp_folder(entity)
    root = entity.root_folder
    temp = root.children.find_by(name: "Temp")
    return temp if temp

    Folder.create!(
      name: "Temp",
      parent: root,
      entity: entity,
      folder_type: :regular
    )
  end

  # Notifies users who have opted in for DB dump notifications via their tag list.
  def notify_users(document)
    # Find active employees of the entity who have 'db_dump_notification' in their tag_list.
    users = document.entity.employees.active.with_tag('db_dump_notification')
    users.each do |user|
      # Use the standard DocumentNotifier to send an email with a download link.
      DocumentNotifier.with(
        record: document,
        entity_id: document.entity_id,
        email_method: :email_link,
        msg: "The daily database dump for #{document.entity.name} is ready for download."
      ).deliver_later(user)
    end
  end

  # Deletes documents tagged as "DB Dump" that are older than the retention period.
  def cleanup_old_dumps(_entity, folder, retention_days)
    threshold = Time.zone.now - retention_days.days
    # We scope by folder and owner_tag to ensure we only delete relevant dumps.
    folder.documents.where(owner_tag: "DB Dump").where(created_at: ...threshold).find_each(&:destroy)
  end
end
