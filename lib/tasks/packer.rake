# lib/tasks/packer.rake
require 'rails' # Load Rails environment to access credentials

namespace :packer do
  PACKER_TEMPLATES_PATH = "config/deploy/templates/packer"

  # Mapping of user-friendly names to Packer template file names
  PACKER_TEMPLATE_MAP = {
    "all" => "*", # Wildcard to build all templates
    "app" => "appserver.ami.pkr.hcl",
    "db" => "db_redis_es.ami.pkr.hcl",
    "obs" => "observability.ami.pkr.hcl"
  }.freeze

  # Helper method to set common environment variables for Packer commands
  def set_packer_env_vars(env)
    # Attempt to load AWS credentials from Rails credentials
    aws_access_key_id = Rails.application.credentials[:AWS_ACCESS_KEY_ID]
    aws_secret_access_key = Rails.application.credentials[:AWS_SECRET_ACCESS_KEY]

    if aws_access_key_id && aws_secret_access_key
      puts "AWS credentials loaded from Rails credentials."
    else
      puts "Warning: AWS credentials (aws_access_key_id or aws_secret_access_key) not found in Rails credentials."
      # Fallback to environment variables if not found in credentials
      aws_access_key_id = ENV['AWS_ACCESS_KEY_ID']
      aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
      if aws_access_key_id && aws_secret_access_key
        puts "AWS credentials loaded from environment variables."
      else
        fail "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set in Rails credentials or environment variables."
      end
    end

    ENV['AWS_ACCESS_KEY_ID'] = aws_access_key_id
    ENV['AWS_SECRET_ACCESS_KEY'] = aws_secret_access_key

    common_vars = {}
    aws_region = "ap-south-1" # Hardcode region for AWS CLI commands

    # Helper to fetch common AWS resource IDs
    def fetch_aws_resource_ids(aws_region, vpc_tag_value)
      resources = {}

      # Dynamically fetch the latest Ubuntu AMI
      resources['source_ami'] = `aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*" "Name=state,Values=available" --query "sort_by(Images, &CreationDate)[-1].ImageId" --output text --region #{aws_region}`.strip

      # Dynamically fetch VPC, Subnet, and Security Group IDs
      vpc_id = `aws ec2 describe-vpcs --filters "Name=tag:Name,Values=#{vpc_tag_value}" --query "Vpcs[0].VpcId" --output text --region #{aws_region}`.strip
      subnet_id = `aws ec2 describe-subnets --filters "Name=vpc-id,Values=#{vpc_id}" "Name=tag:Name,Values=public-subnet-1-*" "Name=map-public-ip-on-launch,Values=true" --query "Subnets[0].SubnetId" --output text --region #{aws_region}`.strip

      all_security_groups_json = `aws ec2 describe-security-groups --filters "Name=vpc-id,Values=#{vpc_id}" --query "SecurityGroups[*].[GroupId,GroupName]" --output json --region #{aws_region}`.strip
      all_security_groups = JSON.parse(all_security_groups_json)

      security_group_id = nil
      all_security_groups.each do |sg_id, sg_name|
        if sg_name =~ /^web-sg-#{aws_region}-.*$/
          security_group_id = sg_id
          break
        end
      end

      if security_group_id.nil? || security_group_id.empty?
        fail "Error: Could not find security group matching pattern web-sg-#{aws_region}-* in VPC #{vpc_id}"
      end

      resources['vpc_id'] = vpc_id
      resources['subnet_id'] = subnet_id
      resources['security_group_id'] = security_group_id

      resources
    end

    case env
    when 'dev'
      resources = fetch_aws_resource_ids(aws_region, "IRM-#{aws_region}-staging")
      common_vars.merge!(resources)
      common_vars['mysql_root_password'] = "Root1234$" # Placeholder, update with actual dev password
      common_vars['ssh_keys_to_copy'] = '["altxdev.pem"]' # Pass as JSON array string

      puts "VPC ID for dev: #{common_vars['vpc_id']}"
      puts "Subnet ID for dev: #{common_vars['subnet_id']}"
      puts "Security Group ID for dev: #{common_vars['security_group_id']}"

    when 'prod'
      resources = fetch_aws_resource_ids(aws_region, "IRM-#{aws_region}-*")
      common_vars.merge!(resources)
      common_vars['mysql_root_password'] = "Root1234$" # Placeholder, update with actual prod password
      common_vars['ssh_keys_to_copy'] = '["caphive2.pem", "caphive.pem"]' # Pass as JSON array string

      puts "VPC ID for prod: #{common_vars['vpc_id']}"
      puts "Subnet ID for prod: #{common_vars['subnet_id']}"
      puts "Security Group ID for prod: #{common_vars['security_group_id']}"
    else
      fail "Unknown environment: #{env}. Please specify 'dev' or 'prod'."
    end

    common_vars['ami_date'] = Time.now.strftime("%Y%m%d%H%M%S") # Set unique AMI date
    common_vars['user_home_dir'] = ENV['HOME'] # Pass the current user's home directory
    common_vars.each do |key, value|
      ENV["PKR_VAR_#{key}"] = value
    end
    ENV['PACKER_LOG'] = '1' # Enable verbose Packer logging
  end

  desc "Check all Packer templates for syntax validity for a specific environment (e.g., rake packer:check_env[dev])"
  task :check_env, [:env] do |t, args|
    env = args[:env] || 'dev'
    set_packer_env_vars(env)
    Dir.glob("#{PACKER_TEMPLATES_PATH}/*.pkr.hcl").each do |template_file|
      puts "Checking Packer template: #{template_file} for environment: #{env}"
      sh "packer validate #{template_file}"
    end
  end

  desc "Check all Packer templates for syntax validity (defaults to dev environment)"
  task :check do
    Rake::Task["packer:check_env"].invoke('dev')
  end

  desc "Initialize all Packer templates for a specific environment (e.g., rake packer:init_env[dev])"
  task :init_env, [:env] do |t, args|
    env = args[:env] || 'dev'
    set_packer_env_vars(env)
    Dir.glob("#{PACKER_TEMPLATES_PATH}/*.pkr.hcl").each do |template_file|
      puts "Initializing Packer template: #{template_file} for environment: #{env}"
      sh "packer init #{template_file}"
    end
  end

  desc "Initialize all Packer templates (defaults to dev environment)"
  task :init do
    Rake::Task["packer:init_env"].invoke('dev')
  end

  desc "Build Packer templates for a specific environment and type (e.g., rake packer:build_env[dev,app] or rake packer:build_env[prod,all])"
  task :build_env, [:env, :template_type] do |t, args|
    env = args[:env] || 'dev'
    template_type = args[:template_type] || 'all' # Default to 'all' if not specified

    set_packer_env_vars(env)

    template_file_name = PACKER_TEMPLATE_MAP[template_type]
    if template_file_name.nil?
      fail "Error: Unknown template type '#{template_type}'. Valid types are: #{PACKER_TEMPLATE_MAP.keys.join(', ')}"
    end

    # Construct the full path, handling the 'all' wildcard
    files_to_build = if template_file_name == "*"
                       Dir.glob("#{PACKER_TEMPLATES_PATH}/*.pkr.hcl")
                     else
                       ["#{PACKER_TEMPLATES_PATH}/#{template_file_name}"]
                     end

    if files_to_build.empty?
      fail "Error: No Packer templates found for type '#{template_type}' in #{PACKER_TEMPLATES_PATH}"
    end

    files_to_build.each do |template_file|
      puts "Building Packer template: #{template_file} for environment: #{env}"
      sh "packer build #{template_file}"
    end
  end

  desc "Build all Packer templates (defaults to dev environment and all templates)"
  task :build do
    Rake::Task["packer:build_env"].invoke('dev', 'all')
  end
end