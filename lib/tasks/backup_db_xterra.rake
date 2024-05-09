require 'rake'
require 'aws-sdk-s3'

# Configuration
MYSQL_USER = Rails.application.credentials[:DB_USER]
MYSQL_PASSWORD = Rails.application.credentials[:DB_PASS]
MYSQL_HOST = Rails.application.credentials[:DB_HOST]
BACKUP_DIR = "./tmp/backup_dir_#{Time.now.strftime('%Y%m%d%H%M%S')}"
INCREMENTAL_DIR = "./tmp/incremental_dir_#{Time.now.strftime('%Y%m%d%H%M%S')}"
DATA_DIR = '/var/lib/mysql'
S3_BUCKET = "#{ENV['AWS_S3_BUCKET']}.db-backup"
DB_NAME = "IRM_#{Rails.env}"
USER = `whoami`.strip
# Helper to create S3 client
def s3_client
  Aws::S3::Client.new(region: ENV["AWS_S3_REGION"])
end

def create_tar_archive(local_path, archive_path)
    sh "tar -czf #{archive_path} -C #{File.dirname(local_path)} #{File.basename(local_path)}"
end

def extract_tar_archive(archive_path, extract_path)
    sh "tar -xzf #{archive_path} -C #{extract_path}"
end

# Helper to upload to S3
def upload_to_s3(local_path, s3_path)
    s3 = Aws::S3::Resource.new(client: s3_client)
    bucket = s3.bucket(S3_BUCKET)
  
    # Create a tar archive of the local directory
    archive_path = "#{local_path}.tar.gz"
    create_tar_archive(local_path, archive_path)
  
    # Upload the tar archive to S3
    puts "Uploading #{archive_path} to S3 bucket #{S3_BUCKET} at #{s3_path}"
    bucket.object("#{s3_path}/#{File.basename(archive_path)}").upload_file(archive_path)
    puts "Uploaded #{archive_path} to S3 bucket #{S3_BUCKET} at #{s3_path}"
  
    # Clean up the local tar archive
    File.delete(archive_path)
end

# Helper to download from S3
def download_from_s3(s3_path, local_path)
    s3 = Aws::S3::Resource.new(client: s3_client)
    bucket = s3.bucket(S3_BUCKET)

    # Download the tar archive from S3
    archive_path = File.join(local_path, "#{File.basename(s3_path)}.tar.gz")
    bucket.object("#{s3_path}.tar.gz").download_file(archive_path)
    puts "Downloaded #{s3_path}.tar.gz from S3 to #{archive_path}"

    # Extract the tar archive
    extract_tar_archive(archive_path, local_path)
    puts "Extracted #{archive_path} to #{local_path}"

    # Clean up the local tar archive
    File.delete(archive_path)
end

namespace :db do
  desc "Perform a full backup of the MySQL database"
  task :full_backup do
    sh "sudo xtrabackup --backup --user=#{MYSQL_USER} --password=#{MYSQL_PASSWORD} --target-dir=#{BACKUP_DIR} --databases=#{DB_NAME}" 
    sh "sudo chown -R #{USER} #{BACKUP_DIR}"
    upload_to_s3(BACKUP_DIR, "full_backup/#{Time.now.strftime('%Y%m%d%H%M%S')}")
  end

  desc "Perform an incremental backup based on the last full or incremental backup"
  task :incremental_backup do    
    # Ensure you have logic here to handle incremental path selection
    sh "sudo xtrabackup --backup --user=#{MYSQL_USER} --password=#{MYSQL_PASSWORD} --target-dir=#{INCREMENTAL_DIR} --incremental-basedir=#{BACKUP_DIR} --databases=#{DB_NAME}"
    sh "sudo chown -R #{USER} #{INCREMENTAL_DIR}"
    upload_to_s3(INCREMENTAL_DIR, "incremental_backup/#{Time.now.strftime('%Y%m%d%H%M%S')}")
  end


  def find_latest_backup(type)
    puts "Finding latest #{type} backup..."
    s3 = Aws::S3::Resource.new(client: s3_client)
    bucket = s3.bucket(S3_BUCKET)

    puts "Listing objects in bucket #{bucket}..."
    
    latest_backup = nil
    latest_timestamp = nil

    bucket.objects(prefix: "#{type}/").each do |obj|
      timestamp = obj.key.split("/").last.to_i
      if latest_timestamp.nil? || timestamp > latest_timestamp
        latest_timestamp = timestamp
        latest_backup = obj.key
      end
    end

    latest_backup
  end

  desc "Restore database from backup"
  task :restore_xterra do
    latest_full_backup = find_latest_backup("full_backup")
    latest_incremental_backup = nil # find_latest_backup("incremental_backup")

    if latest_full_backup.nil?
      puts "No full backup found for restoration."
      return
    end

    download_from_s3(latest_full_backup, BACKUP_DIR)

    if latest_incremental_backup
      download_from_s3(latest_incremental_backup, INCREMENTAL_DIR)
    end

    Rake::Task["db:prepare_backup"].invoke
    sh "sudo service mysql stop"
    sh "sudo rm -rf #{DATA_DIR}/*"
    sh "sudo xtrabackup --copy-back --target-dir=#{BACKUP_DIR}"
    sh "sudo chown -R mysql:mysql #{DATA_DIR}"
    sh "sudo service mysql start"
    puts "Database restoration completed."
  end
end
