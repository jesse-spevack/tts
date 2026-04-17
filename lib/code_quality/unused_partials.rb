# frozen_string_literal: true

module CodeQuality
  # Detects Rails view partials (`_*.html.erb`) that are never referenced from
  # any template or Ruby file under the provided source roots.
  #
  # Usage:
  #   CodeQuality::UnusedPartials.new(
  #     views_root: Rails.root.join("app/views").to_s,
  #     source_roots: [
  #       Rails.root.join("app/views").to_s,
  #       Rails.root.join("app/models").to_s,
  #       Rails.root.join("app/controllers").to_s,
  #       Rails.root.join("app/helpers").to_s,
  #       Rails.root.join("app/jobs").to_s,
  #       Rails.root.join("app/mailers").to_s
  #     ]
  #   ).call
  #   # => { unused: ["shared/foo", ...], total: 234, referenced: 198 }
  #
  # Detection rules (see test file for full behavior spec):
  #   - Enumerates `_*.html.erb` under views_root as render-form names
  #     (directory-relative path minus leading underscore and `.html.erb`).
  #   - Scans `.erb` and `.rb` files under source_roots for references.
  #   - Strips ERB comments (`<%#...%>`) before scanning.
  #   - Recognizes `render "x/y"`, `render partial: "x/y"`, `render layout: "x/y"`,
  #     and `partial: "x/y"` in arbitrary Ruby calls (e.g. `broadcast_replace_to`).
  #   - Resolves relative bare-name refs (`render "foo"` with no slash) against
  #     the referring template's directory.
  #   - Treats any partial whose render-form name starts with a dynamic-prefix
  #     (LHS of `#{`) as referenced (e.g. `render "shared/icons/#{name}"`).
  #   - Walks partial-to-partial references transitively to fixed point.
  class UnusedPartials
    # ERB comments: `<%# ... %>`. Stripped before scanning so that usage
    # examples embedded in partial docs don't register as references.
    ERB_COMMENT = /<%#.*?%>/m

    # Static string render forms: `render "x/y"`, `render("x/y")`,
    # and `render layout: "x/y"`. Captures the path literal.
    # Rejects strings containing `#` (dynamic interpolation is handled
    # separately by DYNAMIC_PREFIX).
    RENDER_STRING = /render(?:\s+|\s*\(\s*)(?:layout:\s*)?"([^"#]+)"/

    # Explicit `partial:` kwarg form — covers `render partial: "x/y"` as well
    # as Ruby calls like `broadcast_replace_to(..., partial: "x/y", ...)`.
    PARTIAL_KWARG = /partial:\s*"([^"#]+)"/

    # Dynamic interpolation: `render "prefix/#{expr}"`. Captures the static
    # prefix (everything before the first `#{`). The prefix is used as a
    # substring match against all partial names — e.g. `shared/icons/` exempts
    # every partial under `shared/icons/`.
    DYNAMIC_PREFIX = /render\s*\(?\s*"([^"]*?)#\{/

    def initialize(views_root:, source_roots:)
      @views_root = views_root
      @source_roots = source_roots
    end

    def call
      partials = enumerate_partials
      partial_set = partials.to_set
      top_level_refs = Set.new
      partial_refs = Hash.new { |h, k| h[k] = Set.new }
      dynamic_prefixes = Set.new

      each_source_file do |path, content|
        stripped = content.gsub(ERB_COMMENT, "")
        refs = extract_refs(stripped, path)
        prefixes = extract_dynamic_prefixes(stripped)

        owner = partial_name_for(path)
        if owner
          refs.each { |r| partial_refs[owner] << r }
          prefixes.each { |p| partial_refs[owner] << [ :prefix, p ] }
        else
          refs.each { |r| top_level_refs << r }
          prefixes.each { |p| dynamic_prefixes << p }
        end
      end

      reachable = reachable_partials(partial_set, top_level_refs, partial_refs, dynamic_prefixes)
      unused = (partials - reachable.to_a).sort

      {
        unused: unused,
        total: partials.length,
        referenced: partials.length - unused.length
      }
    end

    private

    # Walk views_root, collect every `_*.html.erb` as a render-form name.
    def enumerate_partials
      Dir.glob(File.join(@views_root, "**", "_*.html.erb")).map do |path|
        partial_name_for(path)
      end.compact
    end

    # Convert a filesystem path under views_root into a render-form name, or
    # nil if the path is not a partial (_*.html.erb) under views_root.
    def partial_name_for(path)
      return nil unless path.end_with?(".html.erb")
      rel = path.sub(/\A#{Regexp.escape(@views_root)}\/?/, "")
      return nil if rel == path # not under views_root

      dir = File.dirname(rel)
      base = File.basename(rel, ".html.erb")
      return nil unless base.start_with?("_")

      name = base.sub(/\A_/, "")
      dir == "." ? name : "#{dir}/#{name}"
    end

    # Iterate over every `.erb` and `.rb` file under source_roots. De-duplicate
    # across overlapping roots (e.g. views_root is usually also a source root).
    def each_source_file
      seen = Set.new
      @source_roots.each do |root|
        Dir.glob(File.join(root, "**", "*.{erb,rb}")).each do |path|
          next if seen.include?(path)
          seen << path
          yield path, File.read(path)
        end
      end
    end

    # Pull every `render "x/y"` and `partial: "x/y"` literal out of content.
    # Bare-name refs (no slash) are resolved against the referring template's
    # directory when that template lives under views_root.
    def extract_refs(content, source_path)
      refs = []
      content.scan(RENDER_STRING) { |m| refs << resolve(m[0], source_path) }
      content.scan(PARTIAL_KWARG) { |m| refs << resolve(m[0], source_path) }
      refs
    end

    # Pull dynamic-prefix sites: the literal portion of `"prefix/#{...}"` that
    # precedes the first `#{`. Empty prefixes ("#{foo}/bar") are ignored.
    def extract_dynamic_prefixes(content)
      prefixes = []
      content.scan(DYNAMIC_PREFIX) do |m|
        prefix = m[0]
        prefixes << prefix unless prefix.empty?
      end
      prefixes
    end

    # If a render ref has no slash, resolve it against the source file's dir.
    # `render "episode_card"` from `app/views/episodes/_episodes_list.html.erb`
    # resolves to `episodes/episode_card`.
    def resolve(ref, source_path)
      return ref if ref.include?("/")

      rel = source_path.sub(/\A#{Regexp.escape(@views_root)}\/?/, "")
      return ref if rel == source_path # source is not under views_root

      dir = File.dirname(rel)
      dir == "." ? ref : "#{dir}/#{ref}"
    end

    # BFS from top-level refs + dynamic-prefix matches + bare-name-resolved
    # refs, expanding through partial→partial edges until no new partial is
    # reached. A partial is reachable iff some top-level template renders it
    # (directly or transitively) OR its name starts with a top-level dynamic
    # prefix. Partials reached ONLY via an unreachable partial remain unused.
    def reachable_partials(partial_set, top_level_refs, partial_refs, dynamic_prefixes)
      reachable = Set.new

      # Seed from top-level references (non-partial templates + .rb files).
      top_level_refs.each { |r| reachable << r if partial_set.include?(r) }

      # Seed from top-level dynamic prefixes: any partial whose name begins
      # with the prefix is reachable.
      dynamic_prefixes.each do |prefix|
        partial_set.each { |p| reachable << p if p.start_with?(prefix) }
      end

      # Fixed-point expansion through partial→partial edges.
      loop do
        added = false
        reachable.to_a.each do |p|
          partial_refs[p].each do |ref|
            if ref.is_a?(Array) && ref[0] == :prefix
              prefix = ref[1]
              partial_set.each do |q|
                if q.start_with?(prefix) && !reachable.include?(q)
                  reachable << q
                  added = true
                end
              end
            elsif partial_set.include?(ref) && !reachable.include?(ref)
              reachable << ref
              added = true
            end
          end
        end
        break unless added
      end

      reachable
    end
  end
end
