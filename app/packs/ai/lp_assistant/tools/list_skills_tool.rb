# frozen_string_literal: true

# Tool that lists available data domain skills for the LP Assistant.
# Reads the YAML frontmatter of each `.md` file in the skills directory
# and returns one summary line per skill (name + description). The LLM
# calls this first to discover which domain to load.
#
# @see LoadSkillTool
# @see LpChatProvider
class ListSkillsTool < RubyLLM::Tool
  description "List available data domains the LP Assistant can query. " \
              "Call this first to discover which topics you can answer. " \
              "Each entry has a name and description — pick the most " \
              "relevant and then call load_skill(skill_name) to fetch its schema."

  SKILLS_DIR = Rails.root.join('app/packs/ai/lp_assistant/skills').freeze

  # @return [String] formatted skill summary, or a fallback when the directory is empty.
  def execute
    entries = Dir.glob(SKILLS_DIR.join('*.md')).map do |path|
      fm = parse_frontmatter(File.read(path))
      name = fm['name'] || File.basename(path, '.md')
      desc = fm['description'] || '(no description)'
      "- #{name}: #{desc}"
    end

    return 'No skills available.' if entries.empty?

    "Available skills:\n#{entries.join("\n")}\n\n" \
      "Call load_skill(skill_name) to get schema and SQL examples for a domain."
  end

  private

  def parse_frontmatter(content)
    match = content.match(/\A---\n(.*?)\n---\n/m)
    return {} unless match

    YAML.safe_load(match[1]) || {}
  rescue Psych::SyntaxError
    {}
  end
end
