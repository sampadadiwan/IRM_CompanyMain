# lib/tasks/xtrabackup.rake

require 'aws-sdk-s3'
require 'fileutils'


namespace :xtrabackup do

  desc "Prepare AWS ENV vars"
  task :setup_env do
    ENV["AWS_ACCESS_KEY_ID"]     = aws_access_key_id
    ENV["AWS_SECRET_ACCESS_KEY"] = aws_secret_access_key
    ENV["AWS_REGION"]            = aws_region
  end

  def config(key, env_var)
    Rails.application.credentials.dig(*key) || ENV[env_var] || raise("Missing config for #{key.join('.')}")
  end

  def aws_region
    config(["AWS_S3_REGION"], "AWS_S3_REGION")
  end

  def s3_client
    @s3_client ||= Aws::S3::Client.new(
      access_key_id: aws_access_key_id,
      secret_access_key: aws_secret_access_key,
      region: aws_region
    )
  end

  def s3_resource
    @s3_resource ||= Aws::S3::Resource.new(client: s3_client)
  end

  def ensure_s3_bucket_exists
    bucket_name = s3_bucket
    bucket = s3_resource.buckets.find { |b| b.name == bucket_name }

    unless bucket
      puts "Creating S3 bucket: #{bucket_name}"
      s3_resource.create_bucket({
                                  acl: "private",
                                  bucket: bucket_name,
                                  create_bucket_configuration: {
                                    location_constraint: aws_region
                                  }
                                })
      puts "S3 bucket #{bucket_name} created successfully."
    else
      puts "S3 bucket #{bucket_name} already exists."
    end
  rescue StandardError => e
    abort("Failed to ensure S3 bucket exists: #{e.message}")
  end

  def mysql_user
    config(["DB_USER"], "DB_USER")
  end

  def mysql_password
    config(["DB_PASS"], "DB_PASS")
  end

  def aws_access_key_id
    config(["AWS_ACCESS_KEY_ID"], "AWS_ACCESS_KEY_ID")
  end

  def aws_secret_access_key
    config(["AWS_SECRET_ACCESS_KEY"], "AWS_SECRET_ACCESS_KEY")
  end

  def s3_bucket
    config(["AWS_S3_BUCKET"], "AWS_S3_BUCKET") + ".db-backup-xbcloud"
  end

  def xtrabackup_bin
    # config([:backups, :xtrabackup_bin], "XTRABACKUP_BIN")
    "xtrabackup"
  end

  def xbcloud_bin
    # config([:backups, :xbcloud_bin], "XBCLOUD_BIN")
    "xbcloud"
  end

  def backup_target_dir
    "/tmp/backup/full_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
  end

  desc "Full backup"
  task full: [:environment, :setup_env] do
    puts "Running FULL backup..."
    ensure_s3_bucket_exists
    FileUtils.mkdir_p(backup_target_dir) # Ensure target directory exists
    cmd = <<~CMD
      #{xtrabackup_bin} \
      --backup \
      --target-dir=#{backup_target_dir} \
      --user=#{mysql_user} \
      --password=#{mysql_password}

      #{xbcloud_bin} put --s3-bucket="#{s3_bucket}" --storage=s3 --parallel=10 #{backup_target_dir}
    CMD

    system(cmd) || abort("FULL backup failed!")
    puts "Full backup complete."
  end

  desc "Incremental backup (needs last full)"
  task incremental: [:environment, :setup_env] do
    base_dir = ENV["BASE_DIR"] || raise("Set BASE_DIR pointing to last full backup")
    puts "Running INCREMENTAL backup from #{base_dir}..."
    ensure_s3_bucket_exists

    inc_dir = "/tmp/backup/inc_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}" # Consistent path
    FileUtils.mkdir_p(inc_dir) # Ensure incremental directory exists

    cmd = <<~CMD
      #{xtrabackup_bin} \
      --backup \
      --target-dir=#{inc_dir} \
      --incremental-basedir=#{base_dir} \
      --user=#{mysql_user} \
      --password=#{mysql_password}

      #{xbcloud_bin} put --s3-bucket="#{s3_bucket}" --storage=s3 --parallel=10 #{inc_dir}
    CMD

    system(cmd) || abort("INCREMENTAL backup failed!")
    puts "Incremental backup complete."
  end

  desc "Restore latest FULL + INCREMENTALS"
  task restore: [:environment, :setup_env] do
    restore_dir = "/restore/#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
    FileUtils.mkdir_p(restore_dir)

    puts "Restoring from S3 bucket #{s3_bucket} into #{restore_dir}..."

    cmd = <<~CMD
      #{xbcloud_bin} get --s3-bucket=#{s3_bucket} --storage=s3 --parallel=10 --prefix=full_ --to=#{restore_dir}/full

      #{xtrabackup_bin} --prepare --apply-log-only --target-dir=#{restore_dir}/full

      #{xbcloud_bin} list --s3-bucket=#{s3_bucket} | grep inc_ | while read inc; do
        #{xbcloud_bin} get --s3-bucket=#{s3_bucket} --storage=s3 --parallel=10 --prefix=$inc --to=#{restore_dir}/$inc
        #{xtrabackup_bin} --prepare --apply-log-only --target-dir=#{restore_dir}/full --incremental-dir=#{restore_dir}/$inc
      done

      echo "Final apply..."
      #{xtrabackup_bin} --prepare --target-dir=#{restore_dir}/full
    CMD

    system(cmd) || abort("Restore failed!")
    puts "Restore complete."
  end
end
