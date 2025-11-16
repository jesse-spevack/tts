module LoggingHelper
  def self.mask_email(email)
    local, domain = email.split("@")
    masked_local = local.length > 2 ? "#{local[0..1]}***" : "***"
    "#{masked_local}@#{domain}"
  end
end
