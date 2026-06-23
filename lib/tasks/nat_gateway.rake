namespace :aws do
  namespace :nat do
    desc "Show current NAT Gateway + route status. Usage: rake aws:nat:status[production.in]"
    task :status, [:env_name] => :environment do |_t, args|
      Rake::Task['aws:environment'].reenable
      Rake::Task['aws:environment'].invoke(args[:env_name])

      require 'aws-sdk-ec2'
      ec2 = Aws::EC2::Client.new
      region = Aws.config[:region]

      route_table = find_private_route_table(ec2, region)
      route = route_table.routes.find { |r| r.destination_cidr_block == '0.0.0.0/0' }

      puts "🌍 Region: #{region}"
      puts "🗺️  Private route table: #{route_table.route_table_id}"
      if route&.nat_gateway_id
        nat = ec2.describe_nat_gateways(nat_gateway_ids: [route.nat_gateway_id]).nat_gateways.first
        puts "🟢 NAT Gateway: #{nat.nat_gateway_id} (state=#{nat.state})"
        nat.nat_gateway_addresses.each { |a| puts "   EIP: #{a.public_ip} (#{a.allocation_id})" }
      else
        puts "🔴 No NAT Gateway attached — route target: #{route&.state || 'missing'} (blackhole if NAT was deleted)"
      end
    end

    desc "Delete the NAT Gateway and release its EIP. Usage: rake aws:nat:delete[production.in]"
    task :delete, [:env_name] => :environment do |_t, args|
      Rake::Task['aws:environment'].reenable
      Rake::Task['aws:environment'].invoke(args[:env_name])

      require 'aws-sdk-ec2'
      ec2 = Aws::EC2::Client.new
      region = Aws.config[:region]

      route_table = find_private_route_table(ec2, region)
      route = route_table.routes.find { |r| r.destination_cidr_block == '0.0.0.0/0' && r.nat_gateway_id }
      raise "No active NAT Gateway route found in #{route_table.route_table_id}" unless route

      nat = ec2.describe_nat_gateways(nat_gateway_ids: [route.nat_gateway_id]).nat_gateways.first
      allocation_ids = nat.nat_gateway_addresses.map(&:allocation_id)

      print "⚠️  Deleting NAT Gateway #{nat.nat_gateway_id} in #{region}. Private subnets will lose internet access. Continue? [y/N] "
      confirm = $stdin.gets&.strip
      unless confirm&.downcase == 'y'
        puts "Aborted."
        next
      end

      puts "🗑️  Deleting NAT Gateway #{nat.nat_gateway_id}..."
      ec2.delete_nat_gateway(nat_gateway_id: nat.nat_gateway_id)
      ec2.wait_until(:nat_gateway_deleted, nat_gateway_ids: [nat.nat_gateway_id])
      puts "✅ NAT Gateway deleted."

      allocation_ids.each do |alloc_id|
        ec2.release_address(allocation_id: alloc_id)
        puts "♻️  Released EIP allocation #{alloc_id}."
      end

      puts "ℹ️  Route #{route_table.route_table_id} 0.0.0.0/0 is now blackholed. Run aws:nat:create[#{args[:env_name]}] to restore connectivity."
    end

    desc "Create a new NAT Gateway in the public subnet and repoint the private route table. Usage: rake aws:nat:create[production.in]"
    task :create, [:env_name] => :environment do |_t, args|
      Rake::Task['aws:environment'].reenable
      Rake::Task['aws:environment'].invoke(args[:env_name])

      require 'aws-sdk-ec2'
      ec2 = Aws::EC2::Client.new
      region = Aws.config[:region]

      public_subnet = find_tagged_resource(ec2.describe_subnets.subnets, "public-subnet-1-#{region}-production")
      raise "Could not find public subnet tagged 'public-subnet-1-#{region}-production'" unless public_subnet

      puts "🌍 Region: #{region}"
      puts "📍 Public subnet: #{public_subnet.subnet_id}"

      puts "🌐 Allocating new Elastic IP..."
      eip = ec2.allocate_address(domain: 'vpc')
      puts "✅ Allocated #{eip.public_ip} (#{eip.allocation_id})"

      puts "🚪 Creating NAT Gateway..."
      nat = ec2.create_nat_gateway(
        subnet_id: public_subnet.subnet_id,
        allocation_id: eip.allocation_id,
        connectivity_type: 'public'
      ).nat_gateway

      puts "⏳ Waiting for NAT Gateway #{nat.nat_gateway_id} to become available (this can take a few minutes)..."
      ec2.wait_until(:nat_gateway_available, nat_gateway_ids: [nat.nat_gateway_id])
      puts "✅ NAT Gateway #{nat.nat_gateway_id} is available."

      route_table = find_private_route_table(ec2, region)
      existing_route = route_table.routes.find { |r| r.destination_cidr_block == '0.0.0.0/0' }

      if existing_route
        puts "🔁 Replacing existing 0.0.0.0/0 route in #{route_table.route_table_id}..."
        ec2.replace_route(
          route_table_id: route_table.route_table_id,
          destination_cidr_block: '0.0.0.0/0',
          nat_gateway_id: nat.nat_gateway_id
        )
      else
        puts "➕ Creating 0.0.0.0/0 route in #{route_table.route_table_id}..."
        ec2.create_route(
          route_table_id: route_table.route_table_id,
          destination_cidr_block: '0.0.0.0/0',
          nat_gateway_id: nat.nat_gateway_id
        )
      end

      puts "✅ Done. Private subnets in #{region} now route through #{nat.nat_gateway_id} (#{eip.public_ip})."
    end

    def find_tagged_resource(resources, name)
      resources.find { |r| r.tags.any? { |t| t.key == 'Name' && t.value == name } }
    end

    def find_private_route_table(ec2, region)
      rt = ec2.describe_route_tables(
        filters: [{ name: 'tag:Name', values: ["private-route-table-#{region}-production"] }]
      ).route_tables.first
      raise "Could not find route table tagged 'private-route-table-#{region}-production'" unless rt

      rt
    end
  end
end
