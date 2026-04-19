module SyntaxHelper
  # Returns Rouge-tokenized HTML for a code snippet, safe to interpolate inside
  # an existing <pre><code>...</code></pre> structure.
  #
  # The caller keeps control of the surrounding <figure>/<pre> wrapper so that
  # per-block styling (e.g. text-[13px] vs text-[12px]) stays in the view where
  # it belongs. This helper only produces the inner tokenized markup.
  #
  #   <pre class="..."><code><%= highlight(:bash, <<~SH) %></code></pre>
  #     curl -X POST https://example.com
  #   SH
  #
  # Supported languages: :bash, :json, :http. Unknown languages fall back to
  # plain-text (HTML-escaped) so the page still renders safely.
  def highlight(lang, code)
    lexer = case lang.to_sym
    when :bash, :shell, :sh then Rouge::Lexers::Shell.new
    when :json              then Rouge::Lexers::JSON.new
    when :http              then Rouge::Lexers::HTTP.new
    # :javascript covers JSON bodies decorated with `//` line
    # comments — the JSON lexer would flag those as errors.
    when :javascript, :js   then Rouge::Lexers::Javascript.new
    else                         Rouge::Lexers::PlainText.new
    end
    # Rouge::Formatters::HTML emits only inline token <span>s (no surrounding
    # <pre>/<code>), which is exactly what we want — the view template provides
    # its own wrapper.
    formatter = Rouge::Formatters::HTML.new
    formatter.format(lexer.lex(code.to_s.chomp)).html_safe
  end
end
