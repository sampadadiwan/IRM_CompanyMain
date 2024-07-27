require 'rake'

namespace :nginx do
  desc "Switch nginx configuration to maintenance or production"
  task :switch, [:nginx_profile] do |t, args|
    # Path to the sites-available and sites-enabled directories
    sites_available_dir = "/etc/nginx/sites-available"
    sites_enabled_dir = "/etc/nginx/sites-enabled"

    puts "Switching nginx configuration to #{args[:nginx_profile]}..."
    # Ensure the nginx_profile argument is provided
    unless args[:nginx_profile]
      puts "Please specify the nginx_profile (maintenance or IRM_#{Rails.env})"
      exit
    end

    # Validate the nginx_profile argument
    nginx_profile = args[:nginx_profile]
    unless ['maintenance', "IRM_#{Rails.env}"].include?(nginx_profile)
      puts "Invalid nginx_profile specified. Use 'maintenance' or 'IRM_#{Rails.env}'."
      exit
    end

    # Define the paths
    available_file = File.join(sites_available_dir, nginx_profile)
    enabled_link = File.join(sites_enabled_dir, "IRM_#{Rails.env}")  # assuming "IRM_#{Rails.env}" is the desired link name

    # Check if the available file exists
    unless File.exist?(available_file)
      puts "The file #{available_file} does not exist."
      exit
    end

    # Remove the existing symbolic link if it exists
    if File.symlink?(enabled_link) || File.exist?(enabled_link)
      # File.delete(enabled_link)
      puts "cd /etc/nginx/sites-enabled; sudo rm #{enabled_link}"
      `cd /etc/nginx/sites-enabled; sudo rm #{enabled_link}`
    end

    # Create the new symbolic link
    # File.symlink(available_file, enabled_link)
    puts "cd /etc/nginx/sites-enabled; sudo ln -s #{available_file}"
    `cd /etc/nginx/sites-enabled; sudo ln -s #{available_file}`

    # Remove the other environment symlink if it exists
    other_env = (nginx_profile == 'maintenance') ? "IRM_#{Rails.env}" : 'maintenance'
    other_enabled_link = File.join(sites_enabled_dir, other_env)

    if File.symlink?(other_enabled_link) || File.exist?(other_enabled_link)
      # File.delete(other_enabled_link)
      puts "cd /etc/nginx/sites-enabled; sudo rm #{other_enabled_link}"
      `cd /etc/nginx/sites-enabled; sudo rm #{other_enabled_link}`
    end

    puts "Switched nginx configuration to #{nginx_profile}."
    `sudo nginx -s reload`
  end
end
