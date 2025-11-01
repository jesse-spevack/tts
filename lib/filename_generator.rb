class FilenameGenerator
  def self.generate(title)
    date = Time.now.strftime("%Y-%m-%d")
    slug = title.strip
                .downcase
                .gsub(/[^\w\s-]/, "")
                .gsub(/\s+/, "-")
                .gsub(/-+/, "-")
                .gsub(/^-+|-+$/, "")
    "#{date}-#{slug}"
  end
end
