

namespace :db do
  desc "Backup database to AWS-S3"

  desc "Backup database to AWS-S3"
  task :reset_replication, [:server_id] => :environment do |t, args|
    args.with_defaults(server_id: '2')
    server_id = args[:server_id]
    AwsUtils.reset_replication(server_id)
  end

  desc "Restore primary database using DbRestoreService"
  task :restore_primary_db => :environment do
    puts "Starting DB restore process..."
    begin
      DbRestoreService.run!(instance_name: "DB-Redis-ES", stop_instance_flag: false)
      puts "DB restore process completed."
    rescue => e
      sleep(10)
      puts User.first
    end
  end

  desc "Restore replica database using DbRestoreService"
  task :restore_replica_db => :environment do
    puts "Starting DB restore process..."
    DbRestoreService.run!(instance_name: "DB-Redis-ES-Replica", stop_instance_flag: false)
    AwsUtils.reset_replication('2')
    puts "DB restore process completed."
  end

  task :reset_replication => :environment do
    AwsUtils.reset_replication('2')
    puts "DB replication reset completed."
  end

end
