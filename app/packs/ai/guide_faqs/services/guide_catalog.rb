# frozen_string_literal: true

# The user guides on disk: their keys (paths under docs/user_guides without ".md") and titles.
# Used by FAQ Manager's guide picker and to validate FaqEntry#guide_key.
module GuideCatalog
  ROOT = Rails.root.join("docs/user_guides").freeze

  module_function

  # @return [Array<String>] e.g. ["agents/call_notice_agent_user_guide", "capital_calls_user_guide", ...]
  def guide_keys
    Dir.glob(ROOT.join("**", "*.md")).map { |path| Pathname.new(path).relative_path_from(ROOT).to_s.delete_suffix(".md") }.sort
  end

  # @param key [String]
  # @return [Boolean]
  def exists?(key)
    key.present? && key.exclude?("..") && ROOT.join("#{key}.md").file?
  end

  # @param key [String]
  # @return [String] the guide's "# Title" without a trailing "User Guide", or the humanised key
  def title(key)
    path = ROOT.join("#{key}.md")
    heading = path.file? ? File.foreach(path).find { |line| line.strip.present? }.to_s : ""
    title = heading.start_with?("# ") ? heading.delete_prefix("# ").strip : key.to_s.split("/").last.humanize.titleize
    title.sub(/\s*[—-]?\s*User Guide\z/i, "")
  end

  # @return [Array<Array(String, String)>] [title, key] pairs for a select
  def options
    guide_keys.map { |key| ["#{title(key)} (#{key})", key] }
  end
end
