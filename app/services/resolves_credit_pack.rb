class ResolvesCreditPack
  INVALID_PACK_MESSAGE = "Invalid credit pack selected"

  def self.call(raw_pack_size)
    size = coerce_size(raw_pack_size)
    pack = size && AppConfig::Credits.find_pack_by_size(size)

    if pack
      Result.success(pack)
    else
      Result.failure(INVALID_PACK_MESSAGE)
    end
  end

  def self.coerce_size(raw_pack_size)
    case raw_pack_size
    when Integer then raw_pack_size
    when String  then Integer(raw_pack_size, 10)
    end
  rescue ArgumentError, TypeError
    nil
  end
  private_class_method :coerce_size
end
