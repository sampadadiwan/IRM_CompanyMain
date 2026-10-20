# frozen_string_literal: true

require "open3"
require "fileutils"

# Builds the code the support machine reads (design card ⑤): a `git archive` of only the paths in
# INCLUDED at one revision, minus EXCLUDED inside them, plus
#   REVISION                    — the sha, shown in the console footer
#   tables_with_entity_id.json  — tables the scope rules require an entity_id filter on (card ⑥)
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
    File.write(File.join(dest, "tables_with_entity_id.json"), JSON.pretty_generate(tables_with_entity_id(File.join(dest, "db/schema.rb"))))
    sha
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
