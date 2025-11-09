class VerifyHashedToken
  def self.call(hashed_token:, raw_token:)
    new(hashed_token: hashed_token, raw_token: raw_token).call
  end

  def initialize(hashed_token:, raw_token:)
    @hashed_token = hashed_token
    @raw_token = raw_token
  end

  def call
    return false if @hashed_token.nil? || @raw_token.nil?

    BCrypt::Password.new(@hashed_token) == @raw_token
  rescue BCrypt::Errors::InvalidHash
    false
  end
end
