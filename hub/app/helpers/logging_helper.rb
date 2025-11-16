module LoggingHelper
  # Masks email address for privacy-safe logging.
  # Shows first 2 characters of local part, masks the rest.
  #
  # Examples:
  #   mask_email("jesse@example.com")  => "je***@example.com"
  #   mask_email("user@company.org")   => "us***@company.org"
  #   mask_email("ab@test.com")        => "***@test.com"
  #   mask_email("a@test.com")         => "***@test.com"
  def self.mask_email(email)
    local, domain = email.split("@")
    masked_local = local.length > 2 ? "#{local[0..1]}***" : "***"
    "#{masked_local}@#{domain}"
  end
end
