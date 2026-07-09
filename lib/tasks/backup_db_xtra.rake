# lib/tasks/xtrabackup.rake

require 'aws-sdk-s3'
require 'fileutils'

namespace :xtrabackup do
  module Helpers
    extend self

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

      if bucket
        puts "S3 bucket #{bucket_name} already exists."
      else
        puts "Creating S3 bucket: #{bucket_name}"
        s3_resource.create_bucket({
                                    acl: "private",
                                    bucket: bucket_name,
                                    create_bucket_configuration: {
                                      location_constraint: aws_region
                                    }
                                  })
        puts "S3 bucket #{bucket_name} created successfully."
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
  end

  desc "Run the xtrabackup script with environment variables set from Rails credentials and .env"
  task generate_backup_script: :environment do
    # Path to the original and temporary script
    original_script_path = Rails.root.join("lib/tasks/db_backup_xtra.sh")
    temp_script_path = Rails.root.join('tmp', "db_backup_xtra_#{Rails.env}.sh")
    puts "Generating backup script from #{original_script_path} to #{temp_script_path}"

    # Read the original script content
    script_content = File.read(original_script_path)

    # Replace placeholders with credentials
    script_content.gsub!('__BUCKET__', ENV.fetch("AWS_S3_BUCKET", nil) + "-backup-xtra")
    script_content.gsub!('__AWS_REGION__', ENV["AWS_S3_REGION"].to_s)
    script_content.gsub!('__AWS_ACCESS_KEY_ID__', Rails.application.credentials.dig("AWS_ACCESS_KEY_ID").to_s)
    script_content.gsub!('__AWS_SECRET_ACCESS_KEY__', Rails.application.credentials.dig("AWS_SECRET_ACCESS_KEY").to_s)
    script_content.gsub!('__MYSQL_PASSWORD__', Rails.application.credentials.dig("DB_PASS").to_s)
    script_content.gsub!('__MYSQL_USER__', Rails.application.credentials.dig("DB_USER").to_s)
    script_content.gsub!('__DATABASE_NAME__', ActiveRecord::Base.connection.current_database)

    # Write the modified content to a temporary script
    File.write(temp_script_path, script_content)
    FileUtils.chmod(0o755, temp_script_path)

    puts "Temporary script created at #{temp_script_path}"

    # Execute the temporary script
    # puts "Executing temporary script: #{temp_script_path} #{command}"
    # system("#{temp_script_path} #{command}")

    # # Clean up the temporary script
    # FileUtils.rm(temp_script_path)
  end

  desc "Prepare AWS ENV vars"
  task :setup_env do
    ENV["AWS_ACCESS_KEY_ID"]     = Helpers.aws_access_key_id
    ENV["AWS_SECRET_ACCESS_KEY"] = Helpers.aws_secret_access_key
    ENV["AWS_REGION"]            = Helpers.aws_region
  end

  # Seeds the SSM parameters the baked backup script reads at runtime (see
  # db_backup_xtra.sh + db_redis_es.ami.pkr.hcl). SSM parameters are REGIONAL:
  # run once per region that hosts DB instances — including the DR region, so
  # a recovered DB server finds its config without any manual seeding mid-DR.
  # Idempotent: --overwrite updates values in place (rotation = re-run).
  # ex: rake "xtrabackup:seed_ssm_params[production.in, ap-south-1]"
  #     rake "xtrabackup:seed_ssm_params[production.in, ap-south-2]"   # DR region
  desc "Seed SSM Parameter Store with DB backup config for baked AMIs (run per region)"
  task :seed_ssm_params, [:env_name, :region] => :environment do |t, args|
    require 'open3'

    env_name = args[:env_name] or raise "env_name required, e.g. production.in"
    region   = args[:region] || ENV["AWS_REGION"] or raise "region required, e.g. ap-south-1"

    # Load the env-specific .env + AWS SDK credentials (same mechanism as the
    # other aws:* tasks use)
    Rake::Task['aws:environment'].reenable
    Rake::Task['aws:environment'].invoke(env_name)

    # Decrypt the env-specific credentials pair (e.g. production.in.yml.enc) —
    # Rails.application.credentials would be the *current* RAILS_ENV's, which is
    # not necessarily the environment we are seeding for.
    creds = Rails.application.encrypted(
      Rails.root.join("config", "credentials", "#{env_name}.yml.enc"),
      key_path: Rails.root.join("config", "credentials", "#{env_name}.key")
    )

    rails_env = env_name.split(".").first # production.in -> production
    prefix = "/irm/#{rails_env}/db_backup"

    params = {
      "mysql_user"    => creds[:DB_USER] || ENV.fetch("DB_USER"),
      "mysql_password" => creds[:DB_PASS] || ENV.fetch("DB_PASS"),
      # Same bucket naming as generate_backup_script (line ~97): <bucket>-backup-xtra
      "bucket"        => "#{ENV.fetch('AWS_S3_BUCKET')}-backup-xtra",
      # Region of the BUCKET (stays fixed in DR) — not the instance's region
      "bucket_region" => ENV.fetch("AWS_S3_REGION"),
      "database_name" => "IRM_#{rails_env}"
    }

    params.each do |key, value|
      raise "Empty value for #{prefix}/#{key} — check credentials/.env for #{env_name}" if value.to_s.empty?

      # Argument-array form: the secret never passes through a shell
      _out, err, status = Open3.capture3(
        "aws", "ssm", "put-parameter",
        "--name", "#{prefix}/#{key}",
        "--value", value.to_s,
        "--type", "SecureString",
        "--overwrite",
        "--region", region
      )
      raise "Failed to seed #{prefix}/#{key} in #{region}: #{err}" unless status.success?

      puts "✅ Seeded #{prefix}/#{key} (#{region})" # value deliberately not printed
    end

    puts "🎉 SSM backup config seeded for #{env_name} in #{region}."
  end
end
