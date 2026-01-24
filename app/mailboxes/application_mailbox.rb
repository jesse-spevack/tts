class ApplicationMailbox < ActionMailbox::Base
  routing /^readtome@/i => :episodes
end
