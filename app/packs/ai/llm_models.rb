module LlmModels
  # Curated list of current models per provider.
  # key_field maps to the column on EntitySetting that holds the API key.
  # A provider only appears in the UI if that key is present on the entity.
  PROVIDERS = {
    openai: {
      key_field: :openai_api_key,
      label: "OpenAI",
      models: [
        ["GPT-5.5",      "gpt-5.5"],
        ["GPT-5.5 Pro",  "gpt-5.5-pro"],
        ["GPT-5.4",      "gpt-5.4"],
        ["GPT-5.4 Pro",  "gpt-5.4-pro"],
        ["GPT-5.4 Mini", "gpt-5.4-mini"],
        ["GPT-5.4 Nano", "gpt-5.4-nano"],
        ["GPT-5 Mini",   "gpt-5-mini"],
        ["GPT-5 Nano",   "gpt-5-nano"]
      ]
    },
    anthropic: {
      key_field: :anthropic_api_key,
      label: "Anthropic",
      models: [
        ["Claude Opus 4.7",   "claude-opus-4-7"],
        ["Claude Sonnet 4.6", "claude-sonnet-4-6"],
        ["Claude Haiku 4.5",  "claude-haiku-4-5-20251001"]
      ]
    },
    gemini: {
      key_field: :gemini_api_key,
      label: "Google Gemini",
      models: [
        ["Gemini 3.1 Pro",  "gemini-3.1-pro-preview"],
        ["Gemini 3 Flash",  "gemini-3-flash-preview"]
      ]
    },
    openrouter: {
      key_field: :openrouter_api_key,
      label: "OpenRouter",
      models: [
        ["Kimi K2.6",              "openrouter/moonshotai/kimi-k2.6"],
        ["Qwen 3.6 Flash",         "openrouter/qwen/qwen3.6-flash"],
        ["Qwen 3.6 Plus",         "openrouter/qwen/qwen3.6-plus"],
        ["DeepSeek V4 Flash",          "openrouter/deepseek/deepseek-v4-flash"],
        ["DeepSeek V4 Pro",          "openrouter/deepseek/deepseek-v4-pro"],
        ["MiniMax M2.7",           "openrouter/minimax/minimax-m2.7"]
      ]
    }
  }.freeze
end
