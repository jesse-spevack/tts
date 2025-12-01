# frozen_string_literal: true

class LlmProcessor
  def self.call(text:, episode:, user:)
    new(text: text, episode: episode, user: user).call
  end

  def initialize(text:, episode:, user:)
    @text = text
    @episode = episode
    @user = user
  end

  def call
    Rails.logger.info "event=llm_request_started episode_id=#{episode.id} input_chars=#{text.length}"

    prompt = UrlProcessingPrompt.build(text: text)
    response = llm_client.ask(prompt)

    Rails.logger.info "event=llm_response_received episode_id=#{episode.id} input_tokens=#{response.input_tokens} output_tokens=#{response.output_tokens}"

    parsed = parse_response(response.content)
    RecordLlmUsage.call(episode: episode, response: response)

    Rails.logger.info "event=llm_request_completed episode_id=#{episode.id} extracted_title=#{parsed['title']}"

    Result.success(
      title: parsed["title"],
      author: parsed["author"],
      description: parsed["description"],
      content: parsed["content"]
    )
  rescue RubyLLM::Error => e
    Rails.logger.error "event=llm_api_error episode_id=#{episode.id} error=#{e.class} message=#{e.message}"
    Result.failure("Failed to process content")
  rescue JSON::ParserError => e
    Rails.logger.error "event=llm_json_parse_error episode_id=#{episode.id} error=#{e.message}"
    Result.failure("Failed to process content")
  end

  private

  attr_reader :text, :episode, :user

  def llm_client
    @llm_client ||= LlmClient.new
  end

  def parse_response(content)
    # Strip markdown code blocks if present
    json_content = content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
    JSON.parse(json_content)
  end

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
