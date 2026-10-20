# frozen_string_literal: true

require "open3"
require "fileutils"

# Builds the code the support machine reads (design card ⑤): a `git archive` of only the paths in
# INCLUDED at one revision, minus EXCLUDED inside them, plus
#   REVISION                    — the sha, shown in the console footer
#   tables_with_entity_id.json  — tables the scope rules require an entity_id filter on (card ⑥)
#   join_map.json               — the real links a table without entity_id may be joined by
#                                 (support-console-tenant-scope, card ② Link list)
# Used by support_console:local_setup (into tmp/) and support_console:publish_code (to S3).
class SupportConsoleCodeArchive
  # X27 — an allow-list, not a deny-list: a new secret file anywhere else is left out by default
  # instead of shipped by default (config/deploy_id_rsa once was). Only what answers "how does the
  # app work": the code, the schema and the product docs. Never ops docs, incidents or infra.
  INCLUDED = %w[app lib config db/schema.rb db/migrate docs/user_guides docs/modules docs/technical
                docs/release_notes Gemfile Gemfile.lock CLAUDE.md].freeze
  # Removed again from inside INCLUDED: credentials, keys and deploy/infra config.
  EXCLUDED = %w[config/credentials config/master.key config/deploy* config/nginx config/S3 config/support_console
                **/*.pem **/*.key **/*id_rsa* **/.env **/.env.*].freeze

  # @param revision [String] a git revision
  # @param dest [Pathname, String] directory to extract into (created; must not exist yet)
  # @return [String] the full sha
  def self.extract(revision, dest)
    sha = git("rev-parse", revision).strip
    FileUtils.mkdir_p(dest)
    # Only the INCLUDED paths that exist at this revision (git archive fails on a missing pathspec).
    paths = git("ls-tree", "--name-only", sha, "--", *INCLUDED).split("\n")
    # git archive | tar -x, then drop what must never reach the machine. No shell: two processes piped.
    Open3.pipeline_r(["git", "archive", "--format=tar", sha, "--", *paths], ["tar", "-x", "-C", dest.to_s],
                     chdir: Rails.root.to_s) do |_out, threads|
      raise "git archive failed for #{sha}" unless threads.all? { |t| t.value.success? }
    end

    EXCLUDED.each { |pattern| Dir.glob(File.join(dest, pattern), File::FNM_DOTMATCH).each { |path| FileUtils.rm_rf(path) } }
    File.write(File.join(dest, "REVISION"), "#{sha}\n")
    schema = File.join(dest, "db/schema.rb")
    File.write(File.join(dest, "tables_with_entity_id.json"), JSON.pretty_generate(tables_with_entity_id(schema)))
    File.write(File.join(dest, "join_map.json"), JSON.pretty_generate(join_map(schema)))
    sha
  end

  # H7, E6 — every real link in the schema, so the scope rules can tell a join along a foreign key
  # from a join on two unrelated numbers:
  #   add_foreign_key "<from>", "<to>"[, column: "<col>"]   → <from>.<col> → <to>.id
  #   a <name>_id column whose plural is a table             → <table>.<name>_id → <names>.id
  #   a <name>_type + <name>_id pair (polymorphic)           → <table>.<name>_id → whichever table
  #                                                            <name>_type names
  # classes gives each table's model class, which a polymorphic <name>_type must name.
  #
  # @param schema_path [String] a db/schema.rb
  # @return [Hash] { "links" => { table => [{ "column", "to" } | { "column", "polymorphic" }] },
  #   "classes" => { table => class name } }
  def self.join_map(schema_path)
    schema = File.read(schema_path)
    columns = schema.scan(/^\s*create_table "([^"]+)".*?\n(.*?)^\s*end$/m).to_h { |table, body| [table, body.scan(/^\s*t\.\w+ "([^"]+)"/).flatten] }
    links = Hash.new { |hash, table| hash[table] = [] }
    # Declared foreign keys first: they are the most reliable
    schema.scan(/^\s*add_foreign_key "([^"]+)", "([^"]+)"(?:, column: "([^"]+)")?/) do |from, to, column|
      links[from] << { "column" => column || "#{to.singularize}_id", "to" => to }
    end
    columns.each do |table, cols|
      cols.each do |column|
        next unless column.end_with?("_id")
        next if links[table].any? { |link| link["column"] == column }

        name = column.delete_suffix("_id")
        if cols.include?("#{name}_type")
          links[table] << { "column" => column, "polymorphic" => "#{name}_type" }
        elsif columns.key?(name.pluralize)
          links[table] << { "column" => column, "to" => name.pluralize }
        end
      end
    end
    { "links" => links.reject { |_table, list| list.empty? }.sort.to_h,
      "classes" => columns.keys.sort.index_with(&:classify) }
  end

  # @param schema_path [String] a db/schema.rb
  # @return [Array<String>] tables that have an entity_id column
  def self.tables_with_entity_id(schema_path)
    tables = []
    current = nil
    File.foreach(schema_path) do |line|
      if (match = line.match(/^\s*create_table "([^"]+)"/))
        current = match[1]
      elsif current && line.match?(/^\s*t\.\w+ "entity_id"/)
        tables << current
        current = nil
      elsif line.match?(/^\s*end\s*$/)
        current = nil
      end
    end
    tables.uniq.sort
  end

  def self.git(*args)
    out, err, status = Open3.capture3("git", *args, chdir: Rails.root.to_s)
    raise "git #{args.join(' ')} failed: #{err}" unless status.success?

    out
  end
end
