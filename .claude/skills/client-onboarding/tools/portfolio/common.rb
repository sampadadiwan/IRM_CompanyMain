# Shared by the portfolio tools: the workspace's mappings/portfolio.yml, the question-id check, source tables, and
# writing upload files. No client logic lives here — every client choice is a yml rule.
require "yaml"
require "json"
require "date"
require "roo"
require "caxlsx"

module Onboarding
  module Portfolio
    module_function

    def yml_path(workspace) = File.join(workspace, "mappings", "portfolio.yml")
    def out_dir(workspace) = File.join(workspace, "out", "portfolio")

    def config(workspace)
      abort "✖ no #{yml_path(workspace)} — the portfolio is not in scope for this client" unless File.exist?(yml_path(workspace))
      YAML.safe_load_file(yml_path(workspace), permitted_classes: [Date])
    end

    # Every `q:` in the yml must be a question id in <client>_client_questions.md (hard rule 8) → the ids used
    def check_questions!(workspace, cfg)
      path = File.join(workspace, "#{cfg.fetch('client')}_client_questions.md")
      abort "✖ #{File.basename(path)} is missing — create it from client-questions-template.md before building (hard rule 8)" unless File.exist?(path)
      text = File.read(path)
      ids = []
      walk = ->(node) { node.is_a?(Hash) ? (ids << node["q"] if node["q"]; node.each_value { walk.(_1) }) : (node.is_a?(Array) && node.each { walk.(_1) }) }
      walk.(cfg)
      ids = ids.map(&:to_s).uniq
      missing = ids.reject { |q| text.match?(/\*\*#{Regexp.escape(q)}\./) }
      abort "✖ question ids used in portfolio.yml but not in #{File.basename(path)}: #{missing.join(', ')}" if missing.any?
      puts "✔ #{ids.size} question ids, all in #{File.basename(path)}: #{ids.sort.join(' ')}"
      ids
    end

    # Collapse every kind of blank (newline, NBSP, BOM U+FEFF) to one space — client names carry all of them, and the
    # importers match companies by exact name
    def clean(value)
      return value unless value.is_a?(String)

      value.delete("﻿").gsub(/[[:space:]]+/, " ").strip
    end

    # The custom-field key the importer derives from a header (FormCustomField.to_name, form_custom_field.rb:310):
    # "Initial Ownership (%)" → "initial_ownership_" — a pre-created field must use exactly this name
    def to_name(label)
      label.strip.split(/\s+/).map(&:capitalize).join(" ").squeeze(" ").tr(" ", "_").downcase.gsub(/[^0-9a-z_]/, "").squeeze("_")
    end

    # A source sheet as [{ header => value }], headers cleaned of "*" and blanks, all-blank rows dropped
    def table(workspace, src)
      sheet = Roo::Spreadsheet.open(File.join(workspace, "source", src.fetch("file"))).sheet(src.fetch("sheet", 0))
      headers = sheet.row(sheet.first_row).map { clean(_1.to_s.delete("*")) }
      ((sheet.first_row + 1)..sheet.last_row).map { |r| headers.zip(sheet.row(r).map { clean(_1) }).to_h }
                                             .reject { |h| h.values.all? { _1.to_s.empty? } }
    end

    # Writes one sheet; date cells get a real Excel date style (never date text — the job parses text by locale)
    def write_xlsx(path, sheet, headers, rows)
      Axlsx::Package.new do |p|
        ds = p.workbook.styles.add_style(format_code: "dd-mmm-yyyy")
        p.workbook.add_worksheet(name: sheet) do |s|
          s.add_row headers
          rows.each do |row|
            types = row.map { |v| v.is_a?(Date) ? :date : (v.is_a?(Numeric) ? :float : :string) }
            s.add_row row, types:, style: row.map { |v| v.is_a?(Date) ? ds : nil }
          end
        end
        p.serialize(path)
      end
      puts format("%-34s %4d rows", File.basename(path), rows.size)
    end
  end
end
