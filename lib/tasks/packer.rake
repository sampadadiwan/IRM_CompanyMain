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
  def set_packer_env_vars(env, env_variant)
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
    # Set AWS_REGION based on env_variant
    aws_region = (env_variant == 'us' ? 'us-east-1' : 'ap-south-1')
    ENV['AWS_REGION'] = aws_region
    if aws_region.nil? || aws_region.empty?
      fail "Error: AWS_REGION environment variable is not set."
    end
    puts "Using AWS Region: #{aws_region}"
    common_vars['aws_region'] = aws_region # Add aws_region to common_vars

    # Helper to create a VPC if it doesn't exist
    def create_vpc_if_not_exists(aws_region, vpc_tag_value)
      puts "Attempting to find VPC with tag Name=#{vpc_tag_value} in region #{aws_region}"
      vpc_id = `aws ec2 describe-vpcs --filters "Name=tag:Name,Values=#{vpc_tag_value}" --query "Vpcs[0].VpcId" --output text --region #{aws_region}`.strip
      puts "Initial VPC ID check result: '#{vpc_id}'"

      if vpc_id.nil? || vpc_id.empty? || vpc_id.strip == "None"
        puts "VPC with tag Name=#{vpc_tag_value} not found. Creating a new VPC..."
        create_vpc_command = "aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=#{vpc_tag_value}}]' --query 'Vpc.VpcId' --output text --region #{aws_region}"
        puts "Executing VPC creation command: #{create_vpc_command}"
        vpc_id = `#{create_vpc_command}`.strip
        puts "VPC creation command raw output: '#{vpc_id}'"
        if vpc_id.nil? || vpc_id.empty? || vpc_id.strip == "None"
          fail "Error: Failed to create VPC with tag Name=#{vpc_tag_value} in region #{aws_region}. Output: '#{vpc_id}'"
        end
        puts "Created VPC with ID: #{vpc_id}"

        # Enable DNS hostnames and resolution
        `aws ec2 modify-vpc-attribute --vpc-id #{vpc_id} --enable-dns-hostnames '{"Value":true}' --region #{aws_region}`
        `aws ec2 modify-vpc-attribute --vpc-id #{vpc_id} --enable-dns-support '{"Value":true}' --region #{aws_region}`
        puts "Enabled DNS support and hostnames for VPC #{vpc_id}"
      else
        puts "VPC with ID: #{vpc_id} already exists."
      end
      vpc_id
    end

    # Helper to fetch common AWS resource IDs
    def fetch_aws_resource_ids(aws_region, env_variant)
      resources = {}

      # Dynamically fetch the latest Ubuntu AMI
      resources['source_ami'] = `aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query "Parameters[0].Value" --output text --region #{aws_region}`.strip

      # Dynamically fetch VPC, Subnet, and Security Group IDs
      vpc_tag_value = "IRM-#{aws_region}"
      vpc_id = create_vpc_if_not_exists(aws_region, vpc_tag_value)
      puts "Fetched VPC ID: #{vpc_id}"

      # Create or get Internet Gateway
      igw_id = `aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=#{vpc_id}" --query "InternetGateways[0].InternetGatewayId" --output text --region #{aws_region}`.strip
      puts "Internet Gateway ID check result: '#{igw_id}'"
      if igw_id.nil? || igw_id.empty? || igw_id.strip == "None"
        puts "Internet Gateway not found for VPC #{vpc_id}. Creating a new Internet Gateway..."
        igw_id = `aws ec2 create-internet-gateway --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=#{vpc_tag_value}-igw}]' --query 'InternetGateway.InternetGatewayId' --output text --region #{aws_region}`.strip
        if igw_id.nil? || igw_id.empty? || igw_id.strip == "None"
          fail "Error: Failed to create Internet Gateway for VPC #{vpc_id}. Output: '#{igw_id}'"
        end
        `aws ec2 attach-internet-gateway --internet-gateway-id #{igw_id} --vpc-id #{vpc_id} --region #{aws_region}`
        puts "Created and attached Internet Gateway: #{igw_id} to VPC #{vpc_id}"
      else
        puts "Internet Gateway: #{igw_id} already exists for VPC #{vpc_id}."
      end

      # Create or get Public Subnet
      subnet_tag_value = "public-subnet-1-#{aws_region}"
      subnet_id = `aws ec2 describe-subnets --filters "Name=vpc-id,Values=#{vpc_id}" "Name=tag:Name,Values=#{subnet_tag_value}" --query "Subnets[0].SubnetId" --output text --region #{aws_region}`.strip
      puts "Subnet ID check result: '#{subnet_id}'"
      if subnet_id.nil? || subnet_id.empty? || subnet_id.strip == "None"
        puts "Subnet with tag Name=#{subnet_tag_value} not found. Creating a new subnet..."
        # Fetch an available availability zone
        availability_zone = `aws ec2 describe-availability-zones --filters "Name=state,Values=available" --query "AvailabilityZones[0].ZoneName" --output text --region #{aws_region}`.strip
        if availability_zone.nil? || availability_zone.empty? || availability_zone.strip == "None"
          fail "Error: No available availability zones found in region #{aws_region}."
        end
        puts "Using Availability Zone: #{availability_zone}"

        subnet_id = `aws ec2 create-subnet --vpc-id #{vpc_id} --cidr-block 10.0.1.0/24 --availability-zone #{availability_zone} --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=#{subnet_tag_value}}]' --query 'Subnet.SubnetId' --output text --region #{aws_region}`.strip
        if subnet_id.nil? || subnet_id.empty? || subnet_id.strip == "None"
          fail "Error: Failed to create Subnet with tag Name=#{subnet_tag_value} in VPC #{vpc_id}. Output: '#{subnet_id}'"
        end
        `aws ec2 modify-subnet-attribute --subnet-id #{subnet_id} --map-public-ip-on-launch --region #{aws_region}`
        puts "Created Subnet with ID: #{subnet_id}"

        # Create or get Route Table and associate with subnet
        route_table_id = `aws ec2 describe-route-tables --filters "Name=vpc-id,Values=#{vpc_id}" "Name=tag:Name,Values=#{vpc_tag_value}-rtb" --query "RouteTables[0].RouteTableId" --output text --region #{aws_region}`.strip
        puts "Route Table ID check result: '#{route_table_id}'"
        if route_table_id.nil? || route_table_id.empty? || route_table_id.strip == "None"
          puts "Route Table not found for VPC #{vpc_id}. Creating a new Route Table..."
          route_table_id = `aws ec2 create-route-table --vpc-id #{vpc_id} --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=#{vpc_tag_value}-rtb}]' --query 'RouteTable.RouteTableId' --output text --region #{aws_region}`.strip
          if route_table_id.nil? || route_table_id.empty? || route_table_id.strip == "None"
            fail "Error: Failed to create Route Table for VPC #{vpc_id}. Output: '#{route_table_id}'"
          end
          `aws ec2 create-route --route-table-id #{route_table_id} --destination-cidr-block 0.0.0.0/0 --gateway-id #{igw_id} --region #{aws_region}`
          puts "Created Route Table: #{route_table_id} and added default route to Internet Gateway."
        else
          puts "Route Table: #{route_table_id} already exists for VPC #{vpc_id}."
        end
        `aws ec2 associate-route-table --subnet-id #{subnet_id} --route-table-id #{route_table_id} --region #{aws_region}`
        puts "Associated Subnet #{subnet_id} with Route Table #{route_table_id}"
      else
        puts "Subnet with ID: #{subnet_id} already exists."
      end

      # Create or get Security Group
      security_group_name = "web-sg-#{aws_region}-#{env_variant}"
      security_group_id = `aws ec2 describe-security-groups --filters "Name=vpc-id,Values=#{vpc_id}" "Name=group-name,Values=#{security_group_name}" --query "SecurityGroups[0].GroupId" --output text --region #{aws_region}`.strip
      puts "Security Group ID check result: '#{security_group_id}'"
      if security_group_id.nil? || security_group_id.empty? || security_group_id.strip == "None"
        puts "Security Group '#{security_group_name}' not found. Creating a new Security Group..."
        security_group_id = `aws ec2 create-security-group --group-name #{security_group_name} --description "Web server security group for #{env_variant} environment" --vpc-id #{vpc_id} --query 'GroupId' --output text --region #{aws_region}`.strip
        if security_group_id.nil? || security_group_id.empty? || security_group_id.strip == "None"
          fail "Error: Failed to create Security Group '#{security_group_name}' in VPC #{vpc_id}. Output: '#{security_group_id}'"
        end
        puts "Created Security Group with ID: #{security_group_id}"

        # Add ingress rules (e.g., SSH from anywhere, HTTP/HTTPS from anywhere)
        `aws ec2 authorize-security-group-ingress --group-id #{security_group_id} --protocol tcp --port 22 --cidr 0.0.0.0/0 --region #{aws_region}`
        `aws ec2 authorize-security-group-ingress --group-id #{security_group_id} --protocol tcp --port 80 --cidr 0.0.0.0/0 --region #{aws_region}`
        `aws ec2 authorize-security-group-ingress --group-id #{security_group_id} --protocol tcp --port 443 --cidr 0.0.0.0/0 --region #{aws_region}`
        puts "Added ingress rules to Security Group #{security_group_id}"
      else
        puts "Security Group with ID: #{security_group_id} already exists."
      end

      resources['vpc_id'] = vpc_id
      resources['subnet_id'] = subnet_id
      resources['security_group_id'] = security_group_id

      resources
    end

    case env
    when 'dev'
      resources = fetch_aws_resource_ids(aws_region, env_variant)
      common_vars.merge!(resources)
      common_vars['mysql_root_password'] = "Root1234$" # Placeholder, update with actual dev password
      if env_variant == 'us'
        common_vars['ssh_keys_to_copy'] = '["altx.us.pem"]' # Pass as JSON array string
      else
        common_vars['ssh_keys_to_copy'] = '["altxdev.pem"]' # Pass as JSON array string
      end

      puts "VPC ID for dev: #{common_vars['vpc_id']}"
      puts "Subnet ID for dev: #{common_vars['subnet_id']}"
      puts "Security Group ID for dev: #{common_vars['security_group_id']}"

    when 'prod'
      resources = fetch_aws_resource_ids(aws_region, env_variant)
      common_vars.merge!(resources)
      common_vars['mysql_root_password'] = "Root1234$" # Placeholder, update with actual prod password
      if env_variant == 'us'
        common_vars['ssh_keys_to_copy'] = '["caphive2.us.pem"]' # Pass as JSON array string
      else
        common_vars['ssh_keys_to_copy'] = '["caphive2.pem", "caphive.pem"]' # Pass as JSON array string
      end

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

  desc "Check all Packer templates for syntax validity for a specific environment (e.g., rake packer:check_env[dev,us])"
  task :check_env, [:env, :env_variant] do |t, args|
    env = args[:env] || 'dev'
    env_variant = args[:env_variant] || 'us' # Default to 'us' if not specified
    set_packer_env_vars(env, env_variant)
    Dir.glob("#{PACKER_TEMPLATES_PATH}/*.pkr.hcl").each do |template_file|
      puts "Checking Packer template: #{template_file} for environment: #{env}, variant: #{env_variant}"
      sh "packer validate #{template_file}"
    end
  end

  desc "Check all Packer templates for syntax validity (defaults to dev environment and 'us' variant)"
  task :check do
    Rake::Task["packer:check_env"].invoke('dev', 'us')
  end

  desc "Initialize all Packer templates for a specific environment (e.g., rake packer:init_env[dev,us])"
  task :init_env, [:env, :env_variant] do |t, args|
    env = args[:env] || 'dev'
    env_variant = args[:env_variant] || 'us' # Default to 'us' if not specified
    set_packer_env_vars(env, env_variant)
    Dir.glob("#{PACKER_TEMPLATES_PATH}/*.pkr.hcl").each do |template_file|
      puts "Initializing Packer template: #{template_file} for environment: #{env}, variant: #{env_variant}"
      sh "packer init #{template_file}"
    end
  end

  desc "Initialize all Packer templates (defaults to dev environment and 'us' variant)"
  task :init do
    Rake::Task["packer:init_env"].invoke('dev', 'us')
  end

  desc "Build Packer templates for a specific environment and type (e.g., rake packer:build_env[dev,us,app] or rake packer:build_env[prod,us,all])"
  task :build_env, [:env, :env_variant, :template_type] do |t, args|
    env = args[:env] || 'dev'
    env_variant = args[:env_variant] || 'us' # Default to 'us' if not specified
    template_type = args[:template_type] || 'all' # Default to 'all' if not specified

    set_packer_env_vars(env, env_variant)

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

  desc "Build all Packer templates (defaults to dev environment, 'us' variant and all templates)"
  task :build do
    Rake::Task["packer:build_env"].invoke('dev', 'us', 'all')
  end
end