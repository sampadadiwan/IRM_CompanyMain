# frozen_string_literal: true

# Tool that loads the full Markdown content of a single LP Assistant skill.
# Returns the schema, business rules, and example SQL queries for one domain.
# Called after list_skills once the LLM has picked the right domain.
#
# @see ListSkillsTool
# @see LpChatProvider
class LoadSkillTool < RubyLLM::Tool
  description "Load the schema and example SQL queries for one data domain. " \
              "Returns table definitions, critical filtering rules, and " \
              "ready-to-adapt SQL examples. Use after list_skills."

  parameter :skill_name,
            type: :string,
            description: "Skill name from list_skills output, e.g. 'fund_ratios'.",
            required: true

  SKILLS_DIR = Rails.root.join('app/packs/ai/lp_assistant/skills').freeze

  # @param skill_name [String] name from list_skills output (sanitized to [a-z0-9_]).
  # @return [String] full markdown of the skill file, or an error string.
  def execute(skill_name:)
    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    safe_name = skill_name.to_s.gsub(/[^a-z0-9_]/i, '')
    return 'Invalid skill name.' if safe_name.empty?

    path = SKILLS_DIR.join("#{safe_name}.md")
    return "Skill '#{skill_name}' not found." unless File.exist?(path)

    content = File.read(path)
    Rails.logger.info("[lp_assistant] LoadSkillTool took #{((Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000).round}ms skill=#{skill_name}")
    content
  end
end
