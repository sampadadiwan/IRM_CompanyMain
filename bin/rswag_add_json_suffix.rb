#!/usr/bin/env ruby

require 'find'

SPEC_DIRS = [
  'spec/requests',
  'spec/integration',
  'spec/api'
]

puts "🔍 Fixing Swagger paths to properly suffix with .json..."

SPEC_DIRS.each do |dir|
  next unless Dir.exist?(dir)

  Find.find(dir) do |file|
    next unless file.end_with?('_spec.rb')

    original = File.read(file)

    # Fix patterns like '/funds/.json/{id}' → '/funds/{id}.json'
    # and '/funds/.json/{id}/edit' → '/funds/{id}.json/edit'
    modified = original.gsub(/path\s+['"]([^'"]+)['"]\s+do/) do |match|
      path = $1

      # Remove any bad .json in the middle like /funds/.json/{id}
      path = path.gsub('/.json/', '/')

      # For dynamic segments, add .json after {id} if not already present
      path = path.gsub(/(\{[^\/]+\})(?!\.json)(?=($|\/))/, '\1.json')

      # For static segments, add .json at the end if missing
      unless path.include?('{') || path.end_with?('.json') || path =~ /\.\w+\//
        path += '.json'
      end

      "path '#{path}' do"
    end

    if modified != original
      File.write(file, modified)
      puts "✅ Updated: #{file}"
    end
  end
end

puts "🎉 All Swagger paths now properly suffixed with .json."
