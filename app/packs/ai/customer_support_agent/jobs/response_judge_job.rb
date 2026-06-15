# frozen_string_literal: true

# Asynchronously scores each CS agent assistant response using an LLM judge.
# Rates Completeness (0-3), Grounding (0-3), Actionability (0-3) and lists issues.
# Upserts into AgentChatMessageFeedback — creates or updates the feedback row.
# Gated on EntitySetting#cs_judge_enabled? — skips entirely if disabled.
#
# @see AgentChatMessageFeedback
class ResponseJudgeJob < ApplicationJob
  queue_as :low
  retry_on StandardError, wait: 5.seconds, attempts: 2

  # @param message_id [Integer] the AgentChatMessage ID to judge
  def perform(message_id)
    message = AgentChatMessage.find_by(id: message_id)
    return unless message&.assistant?

    session = message.agent_chat_session
    entity = session.support_agent.entity
    return unless entity.entity_setting.cs_judge_enabled?

    user_message = previous_user_message(message)
    return unless user_message

    scores = call_judge(entity, user_message.content, message.content)
    return unless scores

    upsert_feedback(message, entity, scores)
  end

  private

  # @return [AgentChatMessage, nil] the user message immediately before this assistant message
  def previous_user_message(message)
    message.agent_chat_session
           .agent_chat_messages
           .where(role: "user")
           .where("id < ?", message.id)
           .order(id: :desc)
           .first
  end

  # Calls the judge LLM with the scoring rubric
  # @return [Hash, nil] parsed scores or nil on failure
  def call_judge(entity, question, response)
    model = entity.entity_setting.cs_judge_model_name
    chat = LlmService.ruby_llm_chat(entity: entity, model: model)
    chat.with_instructions(judge_system_prompt)

    result = chat.ask(judge_user_prompt(question, response))
    parse_judge_response(result.content.to_s)
  rescue StandardError => e
    Rails.logger.error "[ResponseJudgeJob] Judge call failed: #{e.class} — #{e.message}"
    nil
  end

  # @return [String] system prompt with scoring rubric
  def judge_system_prompt
    <<~PROMPT
      You are a response quality judge for a customer support AI assistant.
      You evaluate assistant responses on three dimensions, each scored 0-3.

      Respond ONLY with valid JSON matching this schema:
      {
        "completeness": <0-3>,
        "grounding": <0-3>,
        "actionability": <0-3>,
        "issues": ["issue1", "issue2"]
      }

      ## Scoring Rubric

      ### Completeness (does it fully answer the question?)
      0 = No answer or completely off-topic
      1 = Partial — missing key information or steps
      2 = Mostly complete — minor gaps
      3 = Fully answers the question with all necessary detail

      ### Grounding (is it based on real data/docs, not hallucinated?)
      0 = Pure hallucination — invented features, fake data
      1 = Mostly ungrounded — vague claims without source
      2 = Mostly grounded — references real features/data, minor inaccuracies
      3 = Fully grounded — all claims traceable to guides or database results

      ### Actionability (can the user act on it immediately?)
      0 = No guidance at all
      1 = Vague suggestions ("you could try...")
      2 = Some actionable steps but incomplete
      3 = Clear step-by-step guidance the user can follow immediately

      ## Issues
      List specific problems found. Examples:
      - "References a menu path that doesn't exist"
      - "Missing step 3 of the workflow"
      - "Cites data that wasn't returned by any tool"
      - "Suggests contacting support instead of answering a question it could answer"

      If the response is perfect, return an empty issues array.
    PROMPT
  end

  # @return [String] user prompt with the question and response to judge
  def judge_user_prompt(question, response)
    <<~PROMPT
      ## User Question
      #{question}

      ## Assistant Response
      #{response}

      Rate this response. Return ONLY the JSON object.
    PROMPT
  end

  # @return [Hash, nil] parsed and validated scores, or nil on parse failure
  def parse_judge_response(raw)
    json_match = raw.match(/\{.*\}/m)
    return nil unless json_match

    parsed = JSON.parse(json_match[0])
    scores = [parsed["completeness"], parsed["grounding"], parsed["actionability"]]
    return nil unless scores.all? { |v| v.is_a?(Integer) && v.between?(0, 3) }

    parsed
  rescue JSON::ParserError
    nil
  end

  # @param message [AgentChatMessage]
  # @param entity [Entity]
  # @param scores [Hash] parsed judge scores
  def upsert_feedback(message, entity, scores)
    feedback = AgentChatMessageFeedback.find_or_create_by!(agent_chat_message_id: message.id) do |f|
      f.entity_id = entity.id
      f.channel = message.channel || "web"
      f.status = "open"
    end

    feedback.with_lock do
      feedback.judge_completeness = scores["completeness"]
      feedback.judge_grounding = scores["grounding"]
      feedback.judge_actionability = scores["actionability"]
      feedback.judge_total = scores["completeness"] + scores["grounding"] + scores["actionability"]
      feedback.judge_issues = scores["issues"]

      feedback.status = "needs_review" if feedback.judge_total < 5 && feedback.status == "open"

      feedback.save!
    end
  end
end
