class ApplicationMailer < ActionMailer::Base
  default from: -> { AppConfig::Domain::MAIL_FROM }
  layout "mailer"
end
