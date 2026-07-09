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
    # Fallback to environment variables if not found in credentials
    aws_access_key_id = ENV['AWS_ACCESS_KEY_ID']
    aws_secret_access_key = ENV['AWS_SECRET_ACCESS_KEY']
    if aws_access_key_id && aws_secret_access_key
      puts "AWS credentials loaded from environment variables."
    else
      fail "Error: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are not set in environment variables."
    end

    common_vars = {}
    # Set AWS_REGION based on env_variant
    aws_region = (env_variant == 'us' ? 'us-east-1' : 'ap-south-1')
    ENV['AWS_REGION'] = aws_region
    if aws_region.nil? || aws_region.empty?
      fail "Error: AWS_REGION environment variable is not set."
    end
    puts "Using AWS Region: #{aws_region}"
    common_vars['aws_region'] = aws_region # Add aws_region to common_vars

    # ------------------------------------------------------------------------
    # Packer build network ("packer-build-<region>").
    #
    # Deliberately SEPARATE from the Pulumi-managed app VPC: AMIs must exist
    # BEFORE the Pulumi stack can be created (the stack config requires AMI
    # ids), so in a brand-new region Packer runs first — there is nothing to
    # reuse. Everything created here is tagged Purpose=packer-build so it can
    # never be mistaken for app infrastructure, and can be removed with
    # rake "packer:teardown_build_network[<region>]".
    # CIDR 10.99.0.0/16 (vs the app VPC's 10.0.0.0/16) makes it obviously
    # not-production in any console listing.
    # ------------------------------------------------------------------------

    def packer_build_tags(name)
      [{ key: "Name", value: name }, { key: "Purpose", value: "packer-build" }]
    end

    # SSH ingress for the build instance: the caller's public IP only — a bake
    # runs a root-credentialed instance and must not be world-reachable.
    # Override with PACKER_SSH_CIDR (e.g. a CI egress range).
    def packer_ssh_cidr
      return ENV["PACKER_SSH_CIDR"] unless ENV["PACKER_SSH_CIDR"].to_s.empty?

      require 'net/http'
      ip = Net::HTTP.get(URI("https://checkip.amazonaws.com")).strip
      fail "Could not determine caller public IP (got '#{ip}') — set PACKER_SSH_CIDR" unless ip.match?(/\A\d{1,3}(\.\d{1,3}){3}\z/)

      "#{ip}/32"
    end

    # Find-or-create the dedicated build network. Idempotent; raises loudly on
    # any AWS failure instead of limping on with empty IDs (the old backtick
    # implementation only ever compared output against the string "None").
    def ensure_build_network(aws_region, env_variant)
      require 'aws-sdk-ec2'
      ec2 = Aws::EC2::Client.new(region: aws_region)
      vpc_name = "packer-build-#{aws_region}"

      # VPC
      vpc = ec2.describe_vpcs(filters: [{ name: "tag:Name", values: [vpc_name] }]).vpcs.first
      if vpc
        vpc_id = vpc.vpc_id
        puts "✅ Build VPC #{vpc_name} exists: #{vpc_id}"
      else
        vpc_id = ec2.create_vpc(
          cidr_block: "10.99.0.0/16",
          tag_specifications: [{ resource_type: "vpc", tags: packer_build_tags(vpc_name) }]
        ).vpc.vpc_id
        ec2.modify_vpc_attribute(vpc_id: vpc_id, enable_dns_hostnames: { value: true })
        ec2.modify_vpc_attribute(vpc_id: vpc_id, enable_dns_support: { value: true })
        puts "🪣 Created build VPC #{vpc_name}: #{vpc_id}"
      end

      # Internet gateway (build instances need outbound for apt/gems/etc.)
      igw = ec2.describe_internet_gateways(filters: [{ name: "attachment.vpc-id", values: [vpc_id] }]).internet_gateways.first
      if igw
        igw_id = igw.internet_gateway_id
      else
        igw_id = ec2.create_internet_gateway(
          tag_specifications: [{ resource_type: "internet-gateway", tags: packer_build_tags("#{vpc_name}-igw") }]
        ).internet_gateway.internet_gateway_id
        ec2.attach_internet_gateway(internet_gateway_id: igw_id, vpc_id: vpc_id)
        puts "🌐 Created + attached build IGW: #{igw_id}"
      end

      # Public subnet in the first available AZ
      subnet_name = "#{vpc_name}-subnet"
      subnet = ec2.describe_subnets(filters: [{ name: "vpc-id", values: [vpc_id] }, { name: "tag:Name", values: [subnet_name] }]).subnets.first
      if subnet
        subnet_id = subnet.subnet_id
      else
        az = ec2.describe_availability_zones(filters: [{ name: "state", values: ["available"] }]).availability_zones.first
        fail "No available AZs in #{aws_region}" unless az

        subnet_id = ec2.create_subnet(
          vpc_id: vpc_id, cidr_block: "10.99.1.0/24", availability_zone: az.zone_name,
          tag_specifications: [{ resource_type: "subnet", tags: packer_build_tags(subnet_name) }]
        ).subnet.subnet_id
        ec2.modify_subnet_attribute(subnet_id: subnet_id, map_public_ip_on_launch: { value: true })

        route_table_id = ec2.create_route_table(
          vpc_id: vpc_id,
          tag_specifications: [{ resource_type: "route-table", tags: packer_build_tags("#{vpc_name}-rtb") }]
        ).route_table.route_table_id
        ec2.create_route(route_table_id: route_table_id, destination_cidr_block: "0.0.0.0/0", gateway_id: igw_id)
        ec2.associate_route_table(subnet_id: subnet_id, route_table_id: route_table_id)
        puts "🛣️ Created build subnet #{subnet_id} (AZ #{az.zone_name}) + route table"
      end

      # Security group: SSH from the caller only — no 80/443 (Packer needs SSH,
      # a build instance serves no web traffic)
      sg_name = "packer-build-sg-#{aws_region}-#{env_variant}"
      sg = ec2.describe_security_groups(filters: [{ name: "vpc-id", values: [vpc_id] }, { name: "group-name", values: [sg_name] }]).security_groups.first
      if sg
        sg_id = sg.group_id
      else
        sg_id = ec2.create_security_group(
          group_name: sg_name, description: "Packer build SSH access (#{env_variant})", vpc_id: vpc_id,
          tag_specifications: [{ resource_type: "security-group", tags: packer_build_tags(sg_name) }]
        ).group_id
        puts "🔐 Created build SG #{sg_name}: #{sg_id}"
      end
      # Ensure the CURRENT caller's IP is authorized (idempotent: duplicate
      # rules raise and are ignored — operator IPs change between bakes)
      begin
        ec2.authorize_security_group_ingress(
          group_id: sg_id,
          ip_permissions: [{ ip_protocol: "tcp", from_port: 22, to_port: 22,
                             ip_ranges: [{ cidr_ip: packer_ssh_cidr, description: "packer operator" }] }]
        )
        puts "🔑 SSH authorized from #{packer_ssh_cidr}"
      rescue Aws::EC2::Errors::InvalidPermissionDuplicate
        puts "✅ SSH already authorized from #{packer_ssh_cidr}"
      end

      { vpc_id: vpc_id, subnet_id: subnet_id, security_group_id: sg_id }
    end

    # Helper to fetch common AWS resource IDs for a bake
    def fetch_aws_resource_ids(aws_region, env_variant)
      resources = {}

      # Latest canonical Ubuntu AMI via the public SSM parameter; fail loudly
      # if unresolvable (network/creds/CLI trouble) instead of passing "" on
      source_ami = `aws ssm get-parameters --names /aws/service/canonical/ubuntu/server/20.04/stable/current/amd64/hvm/ebs-gp3/ami-id --query "Parameters[0].Value" --output text --region #{aws_region}`.strip
      fail "Could not resolve Ubuntu source AMI in #{aws_region} (got '#{source_ami}')" if source_ami.empty? || source_ami == "None"

      resources['source_ami'] = source_ami

      network = ensure_build_network(aws_region, env_variant)
      resources['vpc_id'] = network[:vpc_id]
      resources['subnet_id'] = network[:subnet_id]
      resources['security_group_id'] = network[:security_group_id]

      resources
    end

    case env
    when 'dev'
      resources = fetch_aws_resource_ids(aws_region, env_variant)
      common_vars.merge!(resources)
      # Root password for the baked DB AMI. Never hardcode: it is baked into every
      # AMI, including a network-reachable root@'%' account (see
      # db_redis_es.ami.pkr.hcl mysql_password_setup). Fail loudly if unset —
      # a bake must never fall back to a known placeholder password.
      common_vars['mysql_root_password'] =
        Rails.application.credentials.dig(:MYSQL_ROOT_PASSWORD) ||
        ENV["MYSQL_ROOT_PASSWORD"] ||
        raise("MYSQL_ROOT_PASSWORD not set: add it to Rails credentials or export it before baking AMIs")
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
      # Same rule as dev above: password comes from credentials/ENV only.
      # Prod AMIs also bake root@'%', so a leaked/hardcoded value here would be
      # a remote-root exposure on every DB instance launched from the AMI.
      common_vars['mysql_root_password'] =
        Rails.application.credentials.dig(:MYSQL_ROOT_PASSWORD) ||
        ENV["MYSQL_ROOT_PASSWORD"] ||
        raise("MYSQL_ROOT_PASSWORD not set: add it to Rails credentials or export it before baking AMIs")
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
    # SSM path baked into the DB AMI (/etc/db_backup.env) — the backup script
    # reads its secrets (mysql creds, bucket) from here at runtime via the
    # instance role, so no credentials are ever baked into the AMI itself.
    # Seed the parameters with: rake "xtrabackup:seed_ssm_params[<env_name>,<region>]"
    common_vars['ssm_prefix'] = "/irm/#{env == 'prod' ? 'production' : 'staging'}/db_backup"
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

  # Removes the dedicated packer-build network in a region (e.g. when a region
  # is decommissioned). Only touches resources tagged Purpose=packer-build —
  # the Pulumi app VPC can never match. Legacy build VPCs from the old
  # implementation (tagged "IRM-<region>", no Purpose tag) are NOT touched;
  # remove those manually once confirmed unused.
  desc "Delete the packer-build network in a region (ex: rake packer:teardown_build_network[ap-south-1])"
  task :teardown_build_network, [:region] do |t, args|
    region = args[:region] or fail "region required, e.g. rake 'packer:teardown_build_network[ap-south-1]'"
    require 'aws-sdk-ec2'
    ec2 = Aws::EC2::Client.new(region: region)

    vpc = ec2.describe_vpcs(filters: [
      { name: "tag:Name", values: ["packer-build-#{region}"] },
      { name: "tag:Purpose", values: ["packer-build"] }
    ]).vpcs.first
    unless vpc
      puts "ℹ️ No packer-build VPC found in #{region} — nothing to do."
      next
    end
    vpc_id = vpc.vpc_id
    puts "🧹 Tearing down packer-build network #{vpc_id} in #{region}"

    # Order matters: SGs and subnets before IGW, IGW before VPC
    ec2.describe_security_groups(filters: [{ name: "vpc-id", values: [vpc_id] }]).security_groups.each do |sg|
      next if sg.group_name == "default" # cannot be deleted; dies with the VPC

      ec2.delete_security_group(group_id: sg.group_id)
      puts "  ✂️ SG #{sg.group_name} (#{sg.group_id})"
    end
    ec2.describe_subnets(filters: [{ name: "vpc-id", values: [vpc_id] }]).subnets.each do |subnet|
      ec2.delete_subnet(subnet_id: subnet.subnet_id)
      puts "  ✂️ Subnet #{subnet.subnet_id}"
    end
    ec2.describe_route_tables(filters: [{ name: "vpc-id", values: [vpc_id] }]).route_tables.each do |rtb|
      next if rtb.associations.any?(&:main) # main route table dies with the VPC

      ec2.delete_route_table(route_table_id: rtb.route_table_id)
      puts "  ✂️ Route table #{rtb.route_table_id}"
    end
    ec2.describe_internet_gateways(filters: [{ name: "attachment.vpc-id", values: [vpc_id] }]).internet_gateways.each do |igw|
      ec2.detach_internet_gateway(internet_gateway_id: igw.internet_gateway_id, vpc_id: vpc_id)
      ec2.delete_internet_gateway(internet_gateway_id: igw.internet_gateway_id)
      puts "  ✂️ IGW #{igw.internet_gateway_id}"
    end
    ec2.delete_vpc(vpc_id: vpc_id)
    puts "✅ packer-build network removed from #{region}."
  end
end