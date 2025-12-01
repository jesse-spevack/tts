
require "json"

# Set development defaults for Google Cloud
ENV["GOOGLE_CLOUD_BUCKET"] ||= "verynormal-tts-podcast"
ENV["GOOGLE_CLOUD_PROJECT"] ||= "very-normal"
ENV["GOOGLE_APPLICATION_CREDENTIALS"] ||= File.expand_path("../../../very-normal-text-to-speech-098b554468a4.json", __dir__)

# Load secrets directly from Kamal
begin
  secrets_output = `kamal secrets print`

  secrets_json_str = secrets_output.lines.find { |line| line.start_with?("SECRETS=") }&.split("=", 2)&.last

  if secrets_json_str
    # Remove escaping to parse JSON properly
    secrets_json_clean = secrets_json_str.gsub("\\", "")

    secrets = JSON.parse(secrets_json_clean)

    # Map with full paths as seen in the secrets output
    ENV["RESEND_API_KEY"] = secrets["keys/tts/add more/RESEND_API_KEY"] if secrets["keys/tts/add more/RESEND_API_KEY"]

    all_loaded = ENV["RESEND_CLIENT_ID"]
    raise "Missing Google API credentials" unless all_loaded
  end
end
