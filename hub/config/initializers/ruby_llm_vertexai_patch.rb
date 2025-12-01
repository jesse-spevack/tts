# frozen_string_literal: true

# Monkey-patch to fix RubyLLM 1.9.1 bug where VertexAI authentication fails
# on GCE with "Expected Array or String, got Hash" error.
#
# Bug: RubyLLM passes `scope:` as keyword argument to Google::Auth.get_application_default
# but that method expects scope as a positional argument.
#
# See: https://github.com/crmne/ruby_llm/blob/main/lib/ruby_llm/providers/vertexai.rb#L43
# Remove this patch once RubyLLM releases a fix.

Rails.application.config.after_initialize do
  next unless defined?(RubyLLM::Providers::VertexAI)

  RubyLLM::Providers::VertexAI.class_eval do
    private

    def initialize_authorizer
      require "googleauth"
      @authorizer = ::Google::Auth.get_application_default(
        [
          "https://www.googleapis.com/auth/cloud-platform",
          "https://www.googleapis.com/auth/generative-language.retriever"
        ]
      )
    rescue LoadError
      raise RubyLLM::Error,
            'The googleauth gem ~> 1.15 is required for Vertex AI. Please add it to your Gemfile: gem "googleauth"'
    end
  end
end
