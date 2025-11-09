class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("MAILER_FROM_ADDRESS", "noreply@tts-hub.example.com")
  layout "mailer"
end
