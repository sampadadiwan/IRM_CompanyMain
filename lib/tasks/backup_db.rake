

namespace :db do  desc "Backup database to AWS-S3"  

  task :backup => :environment do
    begin
      BackupDbJob.perform_now
    rescue => e
      ExceptionNotifier.notify_exception(e)
      raise e
    end
  end

  desc 'Test the latest database backup from S3'
  task :restore, [:restore_db_name, :db_host] => :environment do |t, args|
    begin
      args.with_defaults(:restore_db_name => :test_db_restore)
      puts "\n#####################"
      puts "Restoring latest backup from S3 for IRM_#{Rails.env} to #{args[:restore_db_name]} on #{args[:db_host]}"
      puts "#######################"

      restore_db_name = args[:restore_db_name]

      host = args[:db_host] == "Primary" ? Rails.application.credentials[:DB_HOST] : Rails.application.credentials[:DB_HOST_REPLICA]

      puts "Restoring latest backup from S3 for IRM_#{Rails.env} to #{restore_db_name} on #{host}"
      BackupDbJob.new.restore_db(restore_db_name:, host:)      
    rescue => e
      ExceptionNotifier.notify_exception(e)
      raise e
    end
  end

  task :backup_and_test => [:environment] do
    begin
      # We touch a user, so that the backup has a timestamp. This will be used to test the restored database
      time = Time.zone.now
      u = User.support_users.first
      u.update_column(:updated_at, time)

      # Backup the DB
      BackupDbJob.perform_now

      # Restore the DB
      BackupDbJob.new.restore_db(test_count_query: "SELECT COUNT(*) FROM users where updated_at = '#{time.strftime("%Y-%m-%d %H:%M:%S.%6N")}'")
    rescue => e
      ExceptionNotifier.notify_exception(e)
      raise e
    end
  end

  desc 'Create a MySQL replica on a different machine'
  task :create_replica, [:skip_restore_backup, :server_id] => :environment do |t, args|
    begin
      args.with_defaults(:skip_restore_backup => false)
      # Pass this in if you want a different server_id, ie when setting up multiple replicas each should have a distinct server_id
      args.with_defaults(server_id: '2')  

      skip_restore_backup = args[:skip_restore_backup]
      server_id = args[:server_id]

      # Connection details for the source database
      source_host = Rails.application.credentials[:DB_HOST]
      source_user = Rails.application.credentials[:DB_USER]
      source_password = Rails.application.credentials[:DB_PASS]
      source_database = "IRM_#{Rails.env}"
      source_port = 3306

      # Connection details for the destination database
      destination_host = Rails.application.credentials[:DB_HOST_REPLICA]
      destination_user = Rails.application.credentials[:DB_USER]
      destination_password = Rails.application.credentials[:DB_PASS]
      destination_database = "IRM_#{Rails.env}"
      destination_port = 3306

      puts "\n#####################"
      puts "Creating a MySQL replica"
      puts "from #{source_host} of database #{source_database}"
      puts "on #{destination_host} for database #{destination_database}"
      puts "#######################"

      # Connect to the source database
      source_client = Mysql2::Client.new(
        host: source_host,
        username: source_user,
        password: source_password,
        database: source_database,
        port: source_port
      )

      # Connect to the destination database
      destination_client = Mysql2::Client.new(
        host: destination_host,
        username: destination_user,
        password: destination_password,
        port: destination_port
      )

      # Get the current binary log file and position from the source
      result = source_client.query('SHOW MASTER STATUS')
      binlog_file = result.first['File']
      binlog_position = result.first['Position']
      puts "Current binary log file: #{binlog_file}, position: #{binlog_position}"

      # Create a new database on the destination
      destination_client.query("CREATE DATABASE IF NOT EXISTS #{destination_database}")

      unless skip_restore_backup
        # Backup the source database
        BackupDbJob.new.backup_db
        # Restore the backup to the destination
        BackupDbJob.new.restore_db(restore_db_name: destination_database, host: destination_host, port: destination_port) 
      end
      
      # Set up replication on the destination
      change_master_query = "CHANGE MASTER TO
        MASTER_HOST='#{source_host}',
        MASTER_USER='#{source_user}',
        MASTER_PORT=#{source_port},
        MASTER_PASSWORD='#{source_password}',
        MASTER_LOG_FILE='#{binlog_file}',
        MASTER_LOG_POS=#{binlog_position}"

      puts "Setting up replication on the destination with query: #{change_master_query}"
      # This is to make the slave different from the master
      puts "Setting server_id to #{server_id}"
      destination_client.query("SET GLOBAL server_id = #{server_id}")
      log_bin_status = destination_client.query("SHOW VARIABLES LIKE 'log_bin'").first
      # Replica should not have binary logging enabled
      if log_bin_status['Value'] == 'ON'
        puts "⚠️  Binary logging is ON — manual action needed to disable it."
        puts "Add to /etc/mysql/conf.d/mysql.cnf \n [mysqld]\nskip-log-bin"
      end

      # Stop and reset the replica
      destination_client.query('STOP REPLICA')
      destination_client.query('RESET REPLICA ALL')
      # Setup the replica
      destination_client.query(change_master_query)
      # Start the replica
      puts 'Starting slave replication on the destination'
      destination_client.query('START REPLICA')
      puts 'Replication setup complete!'

      destination_client.query('SHOW REPLICA STATUS')
    rescue => e
      ExceptionNotifier.notify_exception(e)
      raise e
    end
  end

  task :reset_replication, [:server_id] => :environment do |t, args|
    args.with_defaults(server_id: '2')
    server_id = args[:server_id]

    # Connection details for the source database
    source_host = Rails.application.credentials[:DB_HOST]
    source_user = Rails.application.credentials[:DB_USER]
    source_password = Rails.application.credentials[:DB_PASS]
    source_database = "IRM_#{Rails.env}"
    source_port = 3306

    # Connection details for the destination database
    destination_host = Rails.application.credentials[:DB_HOST_REPLICA]
    destination_user = Rails.application.credentials[:DB_USER]
    destination_password = Rails.application.credentials[:DB_PASS]
    destination_database = "IRM_#{Rails.env}"
    destination_port = 3306

    # Get the current binary log file and position from the source
    result = source_client.query('SHOW MASTER STATUS')
    binlog_file = result.first['File']
    binlog_position = result.first['Position']
    puts "Current binary log file: #{binlog_file}, position: #{binlog_position}"

    # Set up replication on the destination
    change_master_query = "CHANGE MASTER TO
    MASTER_HOST='#{source_host}',
    MASTER_USER='#{source_user}',
    MASTER_PORT=#{source_port},
    MASTER_PASSWORD='#{source_password}',
    MASTER_LOG_FILE='#{binlog_file}',
    MASTER_LOG_POS=#{binlog_position}"

    puts "Setting up replication on the destination with query: #{change_master_query}"
    # This is to make the slave different from the master
    puts "Setting server_id to #{server_id}"
    destination_client.query("SET GLOBAL server_id = #{server_id}")
    # Stop and reset the replica
    destination_client.query('STOP REPLICA')
    destination_client.query('RESET REPLICA ALL')
    # Setup the replica
    destination_client.query(change_master_query)
    # Start the replica
    puts 'Starting slave replication on the destination'
    destination_client.query('START REPLICA')
    puts 'Replication setup complete!'

    destination_client.query('SHOW REPLICA STATUS')
  end
  
end
