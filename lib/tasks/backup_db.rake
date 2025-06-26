

namespace :db do  desc "Backup database to AWS-S3"  

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
