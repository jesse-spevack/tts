# frozen_string_literal: true

class LlmProcessor
  MAX_INPUT_CHARS = 100_000 # ~25k tokens, well within Gemini context window
  MAX_TITLE_LENGTH = 255
  MAX_AUTHOR_LENGTH = 255
  MAX_DESCRIPTION_LENGTH = 1000

  def self.call(text:, episode:)
    new(text: text, episode: episode).call
  end

  def initialize(text:, episode:)
    @text = text
    @episode = episode
  end

  def call
    Rails.logger.info "event=llm_request_started episode_id=#{episode.id} input_chars=#{text.length}"

    if text.length > MAX_INPUT_CHARS
      Rails.logger.warn "event=llm_input_too_large episode_id=#{episode.id} input_chars=#{text.length} max_chars=#{MAX_INPUT_CHARS}"
      return Result.failure("Article content too large for processing")
    end

    prompt = build_prompt
    response = llm_client.ask(prompt)

    Rails.logger.info "event=llm_response_received episode_id=#{episode.id} input_tokens=#{response.input_tokens} output_tokens=#{response.output_tokens}"

    parsed = parse_response(response.content)
    validated = validate_and_sanitize(parsed)
    RecordLlmUsage.call(episode: episode, response: response)

    Rails.logger.info "event=llm_request_completed episode_id=#{episode.id} extracted_title=#{validated[:title]}"

    Result.success(**validated)
  rescue RubyLLM::Error => e
    Rails.logger.error "event=llm_api_error episode_id=#{episode.id} error=#{e.class} message=#{e.message}"

    Result.failure("Failed to process content")
  rescue JSON::ParserError => e
    Rails.logger.error "event=llm_json_parse_error episode_id=#{episode.id} error=#{e.message}"

    Result.failure("Failed to process content")
  rescue ValidationError => e
    Rails.logger.error "event=llm_validation_error episode_id=#{episode.id} error=#{e.message}"

    Result.failure("Failed to process content")
  end

  private

  attr_reader :text, :episode

  def llm_client
    @llm_client ||= CallsLlm.new
  end

  def build_prompt
    if episode.paste?
      PasteProcessingPrompt.build(text: text)
    else
      UrlProcessingPrompt.build(text: text)
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
      title: truncate(extract_string(parsed, "title", "Untitled"), MAX_TITLE_LENGTH),
      author: truncate(extract_string(parsed, "author", "Unknown"), MAX_AUTHOR_LENGTH),
      description: truncate(extract_string(parsed, "description", ""), MAX_DESCRIPTION_LENGTH),
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

  class Result
    attr_reader :title, :author, :description, :content, :error

    def self.success(title:, author:, description:, content:)
      new(title: title, author: author, description: description, content: content, error: nil)
    end

    def self.failure(error)
      new(title: nil, author: nil, description: nil, content: nil, error: error)
    end

    def initialize(title:, author:, description:, content:, error:)
      @title = title
      @author = author
      @description = description
      @content = content
      @error = error
    end

    def success?
      error.nil?
    end

    def failure?
      !success?
    end
  end
end
