class PublishParamsValidator
  def initialize(params)
    @params = params
  end

  def validate
    errors = []
    errors.concat(validate_text_fields)
    errors.concat(validate_content_file)
    errors
  end

  private

  def validate_text_fields
    errors = []
    errors << "Missing title" if missing_or_empty?(@params[:title])
    errors << "Missing author" if missing_or_empty?(@params[:author])
    errors << "Missing description" if missing_or_empty?(@params[:description])
    errors
  end

  def validate_content_file
    return ["Missing content"] if @params[:content].nil?

    content_file = @params[:content]
    return ["Missing content"] unless valid_file_hash?(content_file)

    validate_file_content(content_file)
  end

  def missing_or_empty?(value)
    value.nil? || value.empty?
  end

  def valid_file_hash?(file)
    file.is_a?(Hash) && file[:tempfile]
  end

  def validate_file_content(content_file)
    content = content_file[:tempfile].read
    content_file[:tempfile].rewind
    content.strip.empty? ? ["Content file is empty"] : []
  end
end
