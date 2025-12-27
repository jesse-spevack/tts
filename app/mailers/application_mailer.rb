class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAILER_FROM_ADDRESS", "noreply@tts.verynormal.dev") }
  layout "mailer"
end
