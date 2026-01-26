# frozen_string_literal: true

class ProcessesWithLlm
  include EpisodeLogging

  LlmData = Struct.new(:title, :author, :description, :content, keyword_init: true)

  def self.call(text:, episode:)
    new(text: text, episode: episode).call
  end

  def initialize(text:, episode:)
    @text = text
    @episode = episode
  end

  def call
    log_info "llm_request_started", input_chars: text.length

    prompt = build_prompt
    response = llm_client.ask(prompt)

    log_info "llm_response_received", input_tokens: response.input_tokens, output_tokens: response.output_tokens

    parsed = parse_response(response.content)
    validated = validate_and_sanitize(parsed)
    RecordsLlmUsage.call(episode: episode, response: response)

    log_info "llm_request_completed", extracted_title: validated[:title]

    Result.success(LlmData.new(**validated))
  rescue RubyLLM::Error => e
    log_error "llm_api_error", error: e.class, message: e.message

    Result.failure("Failed to process content")
  rescue JSON::ParserError => e
    log_error "llm_json_parse_error", error: e.message

    Result.failure("Failed to process content")
  rescue ValidationError => e
    log_error "llm_validation_error", error: e.message

    Result.failure("Failed to process content")
  end

  private

  attr_reader :text, :episode

  def llm_client
    @llm_client ||= AsksLlm.new
  end

  def build_prompt
    case
    when episode.paste?
      BuildsPasteProcessingPrompt.call(text: text)
    when episode.email?
      BuildsEmailProcessingPrompt.call(text: text)
    else
      BuildsUrlProcessingPrompt.call(text: text)
    end
  end

  def parse_response(content)
    # Strip markdown code blocks if present
    json_content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
    JSON.parse(json_content)
  end

  def validate_and_sanitize(parsed)
    content = extract_string(parsed, "content")
    raise ValidationError, "Missing content in LLM response" if content.blank?

    {
      title: truncate(extract_string(parsed, "title", "Untitled"), AppConfig::Llm::MAX_TITLE_LENGTH),
      author: truncate(extract_string(parsed, "author", "Unknown"), AppConfig::Llm::MAX_AUTHOR_LENGTH),
      description: truncate(extract_string(parsed, "description", ""), AppConfig::Llm::MAX_DESCRIPTION_LENGTH),
      content: content
    }
  end

  def extract_string(hash, key, default = nil)
    value = hash[key]
    return default unless value.is_a?(String)

    value.strip.presence || default
  end

  def truncate(string, max_length)
    return "" if string.nil?

    string.length > max_length ? "#{string[0, max_length - 3]}..." : string
  end

  class ValidationError < StandardError; end
end
