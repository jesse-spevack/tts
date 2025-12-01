RubyLLM.configure do |config|
  config.vertexai_project_id = ENV["GOOGLE_CLOUD_PROJECT"]
  config.vertexai_location = ENV.fetch("VERTEX_AI_LOCATION", "us-west3")
end
