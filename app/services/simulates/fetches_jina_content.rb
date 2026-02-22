# frozen_string_literal: true

module Simulates
  module FetchesJinaContent
    include StructuredLogging

    def call
      log_info "simulation_jina_fetch_started", url: url

      sleep(rand(0.3..1.0))

      content = "Simulated article content from Jina reader service. " \
                "This placeholder text is returned by simulation mode to avoid " \
                "external API calls. The content is long enough to pass quality checks. " * 5

      log_info "simulation_jina_fetch_completed", url: url, chars: content.length
      Result.success(content)
    end
  end
end
