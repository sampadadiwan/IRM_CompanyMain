module SupportAgentsHelper
  # Converts a LONG_DESCRIPTION heredoc into a fully structured HTML panel.
  #
  # Parsing rules (applied to blank-line-separated blocks):
  #   • Blocks containing "• item" lines → pipeline-steps section
  #   • Blocks starting with "Config:" → config-badges section
  #   • All other blocks → intro paragraph
  #
  # Each bullet item may span multiple lines; continuation lines are joined
  # onto the preceding bullet automatically.
  def format_agent_description(text)
    return "".html_safe if text.blank?

    sections = parse_agent_description_sections(text)
    parts    = sections.filter_map { |s| render_agent_description_section(s) }
    safe_join(parts)
  end

  private

  # Splits the text into typed sections.
  def parse_agent_description_sections(text)
    text.strip.split(/\n\n+/).map do |block|
      lines = block.strip.split("\n")
      if lines.any? { |l| l.strip.start_with?("•") }
        parse_bullets_block(lines)
      else
        joined = lines.map(&:strip).reject(&:empty?).join(" ")
        if joined.match?(/\AConfig:/i)
          { type: :config, text: joined.sub(/\AConfig:\s*/i, "") }
        else
          { type: :intro, text: joined }
        end
      end
    end
  end

  # Parses a block that contains "• bullet" lines, accumulating continuation lines.
  def parse_bullets_block(lines)
    header_lines = []
    items        = []
    current      = nil

    lines.each do |line|
      stripped = line.strip
      if stripped.start_with?("•")
        items << current if current
        current = stripped.sub(/\A•\s*/, "")
      elsif current.nil?
        header_lines << stripped unless stripped.empty?
      else
        current += " #{stripped}" unless stripped.empty?
      end
    end
    items << current if current

    { type: :steps, header: header_lines.join(" ").chomp(":"), items: items }
  end

  # Renders one parsed section into HTML.
  def render_agent_description_section(section)
    case section[:type]
    when :intro
      content_tag(:p, section[:text], class: "agent-about-intro")
    when :steps
      render_steps_section(section)
    when :config
      render_config_section(section)
    end
  end

  def render_steps_section(section)
    header_html = (content_tag(:div, section[:header], class: "agent-section-label") if section[:header].present?)

    step_tags = section[:items].each_with_index.map do |item, idx|
      if item.include?(" — ")
        title, body = item.split(" — ", 2)
      else
        title = item
        body  = nil
      end

      content_tag(:div, class: "agent-step") do
        badge = content_tag(:div, (idx + 1).to_s, class: "agent-step-num")
        inner = content_tag(:div, title, class: "agent-step-title")
        inner += content_tag(:div, body, class: "agent-step-body") if body.present?
        badge + content_tag(:div, inner)
      end
    end
    steps_html = safe_join(step_tags)

    content_tag(:div, class: "agent-steps-section") do
      safe_join([header_html, content_tag(:div, steps_html, class: "agent-steps")])
    end
  end

  def render_config_section(section)
    # Extract the first token of each comma-separated clause as the param name
    param_names = section[:text].split(/,\s*(?=[a-z_]+[\s(])/).filter_map do |clause|
      clause.strip.split(/[\s(]/)[0]
    end.reject(&:empty?).uniq

    badges = safe_join(param_names.map { |p| content_tag(:span, p, class: "agent-config-badge") }, " ")

    content_tag(:div, class: "agent-config-section") do
      content_tag(:span, "Config", class: "agent-section-label me-2") + badges
    end
  end
end
