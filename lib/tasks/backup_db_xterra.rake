# lib/tasks/xtrabackup.rake

namespace :xtrabackup do
  def config(key, env_var)
    Rails.application.credentials.dig(*key) || ENV[env_var] || raise("Missing config for #{key.join('.')}")
  end

  def mysql_user
    config([:mysql, :user], "DB_USER")
  end

  def mysql_password
    config([:mysql, :password], "DB_PASS")
  end

  def aws_access_key_id
    config([:aws, :access_key_id], "AWS_ACCESS_KEY_ID")
  end

  def aws_secret_access_key
    config([:aws, :secret_access_key], "AWS_SECRET_ACCESS_KEY")
  end

  def s3_bucket
    config([:backups, :s3_bucket], "BACKUP_S3_BUCKET")
  end

  def xtrabackup_bin
    config([:backups, :xtrabackup_bin], "XTRABACKUP_BIN")
  end

  def xbcloud_bin
    config([:backups, :xbcloud_bin], "XBCLOUD_BIN")
  end

  def backup_target_dir
    "/backup/full_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
  end

  desc "Full backup"
  task full: :environment do
    puts "Running FULL backup..."
    cmd = <<~CMD
      #{xtrabackup_bin} \
      --backup \
      --target-dir=#{backup_target_dir} \
      --user=#{mysql_user} \
      --password=#{mysql_password}

      #{xbcloud_bin} put --bucket=#{s3_bucket} --storage=aws --parallel=10 #{backup_target_dir}
    CMD

    system(cmd) || abort("FULL backup failed!")
    puts "Full backup complete."
  end

  desc "Incremental backup (needs last full)"
  task incremental: :environment do
    base_dir = ENV["BASE_DIR"] || raise("Set BASE_DIR pointing to last full backup")
    puts "Running INCREMENTAL backup from #{base_dir}..."

    inc_dir = "/backup/inc_#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"

    cmd = <<~CMD
      #{xtrabackup_bin} \
      --backup \
      --target-dir=#{inc_dir} \
      --incremental-basedir=#{base_dir} \
      --user=#{mysql_user} \
      --password=#{mysql_password}

      #{xbcloud_bin} put --bucket=#{s3_bucket} --storage=aws --parallel=10 #{inc_dir}
    CMD

    system(cmd) || abort("INCREMENTAL backup failed!")
    puts "Incremental backup complete."
  end

  desc "Restore latest FULL + INCREMENTALS"
  task restore: :environment do
    restore_dir = "/restore/#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}"
    FileUtils.mkdir_p(restore_dir)

    puts "Restoring from S3 bucket #{s3_bucket} into #{restore_dir}..."

    cmd = <<~CMD
      #{xbcloud_bin} get --bucket=#{s3_bucket} --storage=aws --parallel=10 --prefix=full_ --to=#{restore_dir}/full

      #{xtrabackup_bin} --prepare --apply-log-only --target-dir=#{restore_dir}/full

      #{xbcloud_bin} list --bucket=#{s3_bucket} | grep inc_ | while read inc; do
        #{xbcloud_bin} get --bucket=#{s3_bucket} --storage=aws --parallel=10 --prefix=$inc --to=#{restore_dir}/$inc
        #{xtrabackup_bin} --prepare --apply-log-only --target-dir=#{restore_dir}/full --incremental-dir=#{restore_dir}/$inc
      done

      echo "Final apply..."
      #{xtrabackup_bin} --prepare --target-dir=#{restore_dir}/full
    CMD

    system(cmd) || abort("Restore failed!")
    puts "Restore complete."
  end
end
