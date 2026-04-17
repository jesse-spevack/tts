# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

# Tests for CodeQuality::UnusedPartials — a pure-Ruby detector for unreferenced
# view partials. Tests use synthetic fixtures under Dir.mktmpdir so the detector
# never touches the real PodRead repo.
#
# Each test writes a tiny fake `app/views/` tree (plus `.rb` sources when
# relevant), runs the detector, and asserts on the `{ unused:, total:, referenced: }`
# return shape.
#
# All tests MUST fail until Implementer fills in the detector logic.
class CodeQuality::UnusedPartialsTest < ActiveSupport::TestCase
  # Parallelize-safe: each test allocates its own tmpdir.
  self.test_order = :random

  setup do
    @tmpdir = Dir.mktmpdir("unused_partials_test")
    @views_root = File.join(@tmpdir, "app", "views")
    FileUtils.mkdir_p(@views_root)
  end

  teardown do
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.directory?(@tmpdir)
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Write a file, creating parent directories as needed.
  def write(relative_path, contents)
    full = File.join(@tmpdir, relative_path)
    FileUtils.mkdir_p(File.dirname(full))
    File.write(full, contents)
    full
  end

  # Build and run the detector with the tmpdir as its views_root. `extra_roots`
  # may supplement the default `app/views` source root with ruby dirs, etc.
  def run_detector(extra_source_roots: [])
    source_roots = [ @views_root ] + extra_source_roots.map { |r| File.join(@tmpdir, r) }
    CodeQuality::UnusedPartials.new(
      views_root: @views_root,
      source_roots: source_roots
    ).call
  end

  # ---------------------------------------------------------------------------
  # Behavior 1: Partial enumeration
  # ---------------------------------------------------------------------------

  test "enumerates _*.html.erb partials under views_root and reports total" do
    write("app/views/shared/_header.html.erb", "hello")
    write("app/views/shared/_footer.html.erb", "bye")
    write("app/views/pages/home.html.erb", "<%= render 'shared/header' %>") # non-partial template
    write("app/views/pages/_banner.html.erb", "banner")

    result = run_detector

    assert_equal 3, result[:total], "expected 3 partials (header, footer, banner); got #{result[:total]}"
  end

  test "ignores non-partial templates (no leading underscore) and non-html.erb files" do
    write("app/views/shared/_real_partial.html.erb", "real")
    write("app/views/shared/regular.html.erb", "not a partial") # no leading underscore
    write("app/views/shared/_not_erb.html", "not erb")           # wrong extension
    write("app/views/shared/_data.json.erb", "json format")      # wrong extension

    result = run_detector

    assert_equal 1, result[:total], "only _real_partial.html.erb should be counted"
  end

  # ---------------------------------------------------------------------------
  # Behavior 2: Static string refs (paren / no-paren / with locals)
  # ---------------------------------------------------------------------------

  test "detects static string render refs with and without parens and with locals" do
    write("app/views/shared/_a.html.erb", "a")
    write("app/views/shared/_b.html.erb", "b")
    write("app/views/shared/_c.html.erb", "c")
    write("app/views/unused/_orphan.html.erb", "never referenced")

    write(
      "app/views/pages/home.html.erb",
      <<~ERB
        <%= render "shared/a" %>
        <%= render("shared/b") %>
        <%= render "shared/c", locals: { name: "x" } %>
      ERB
    )

    result = run_detector

    assert_equal [ "unused/orphan" ], result[:unused]
    assert_equal 4, result[:total]
    assert_equal 3, result[:referenced]
  end

  # ---------------------------------------------------------------------------
  # Behavior 3: Layout form — `render layout: "x/y" do ... end`
  # ---------------------------------------------------------------------------

  test "detects partial used as layout via render layout: form" do
    write("app/views/shared/_card.html.erb", "<%= yield %>")
    write("app/views/shared/_unused.html.erb", "orphan")

    write(
      "app/views/pages/index.html.erb",
      <<~ERB
        <%= render layout: "shared/card" do %>
          <p>body</p>
        <% end %>
      ERB
    )

    result = run_detector

    assert_equal [ "shared/unused" ], result[:unused]
  end

  # ---------------------------------------------------------------------------
  # Behavior 4: Explicit kwarg form — `render partial: "x/y"`
  # ---------------------------------------------------------------------------

  test "detects explicit kwarg form render partial: 'x/y'" do
    write("app/views/shared/_explicit.html.erb", "explicit")
    write("app/views/shared/_orphan.html.erb", "orphan")

    write(
      "app/views/pages/show.html.erb",
      %q(<%= render partial: "shared/explicit", locals: { foo: 1 } %>)
    )

    result = run_detector

    assert_equal [ "shared/orphan" ], result[:unused]
  end

  # ---------------------------------------------------------------------------
  # Behavior 5: Ruby `partial:` kwarg in non-render calls (e.g. broadcast_replace_to)
  # ---------------------------------------------------------------------------

  test "detects partial: kwarg inside ruby files (broadcast_replace_to pattern)" do
    write("app/views/episodes/_episode_card.html.erb", "card")
    write("app/views/shared/_unused.html.erb", "orphan")

    # Simulate app/models/episode.rb:60 — broadcast_replace_to ..., partial: "..."
    write(
      "app/models/episode.rb",
      <<~RUBY
        class Episode < ApplicationRecord
          after_update_commit do
            broadcast_replace_to(
              "episodes",
              target: "episode_\#{id}",
              partial: "episodes/episode_card",
              locals: { episode: self }
            )
          end
        end
      RUBY
    )

    # Also ensure a top-level template keeps episode_card "anchored" — no, we
    # want to confirm that the `.rb` ref alone is sufficient. So DO NOT render
    # episode_card from any template.
    write("app/views/pages/home.html.erb", "<p>no partial refs here</p>")

    result = run_detector(extra_source_roots: [ "app/models" ])

    assert_includes result[:unused], "shared/unused"
    refute_includes result[:unused], "episodes/episode_card",
      "partial: kwarg in a .rb file should mark episodes/episode_card as referenced"
  end

  # ---------------------------------------------------------------------------
  # Behavior 6: Relative bare-name resolution
  # ---------------------------------------------------------------------------

  test "resolves relative bare-name render refs against referring template's directory" do
    # Mirrors PodRead's `render 'episode_card'` inside app/views/episodes/_episodes_list.html.erb
    write("app/views/episodes/_episode_card.html.erb", "card")
    write("app/views/episodes/_pagination.html.erb", "pag")
    write("app/views/episodes/index.html.erb", '<%= render "episodes_list" %>') # bare-name from index
    write("app/views/episodes/_episodes_list.html.erb", <<~ERB)
      <%= render "episode_card" %>
      <%= render "pagination" %>
    ERB
    # And an unrelated orphan in a different dir
    write("app/views/shared/_orphan.html.erb", "orphan")

    result = run_detector

    assert_equal [ "shared/orphan" ], result[:unused],
      "bare-name refs should resolve to <referring-template-dir>/<name>; episode_card, pagination, and episodes_list should all be reachable"
  end

  # ---------------------------------------------------------------------------
  # Behavior 7: Dynamic prefix exemption — `render "shared/icons/#{name}"`
  # ---------------------------------------------------------------------------

  test "exempts all partials under a dynamic-interpolation prefix" do
    # Simulate shared/icons with 3 icons, none referenced by literal name
    write("app/views/shared/icons/_check.html.erb", "check")
    write("app/views/shared/icons/_x_mark.html.erb", "x")
    write("app/views/shared/icons/_arrow.html.erb", "arrow")
    # Plus a non-icon orphan that should still be flagged
    write("app/views/shared/_orphan.html.erb", "orphan")

    # Dynamic render — prefix is everything before #{
    write(
      "app/views/pages/icons_gallery.html.erb",
      '<%= render "shared/icons/#{name}", css_class: "size-5" %>'
    )

    result = run_detector

    assert_equal [ "shared/orphan" ], result[:unused],
      "all partials under shared/icons/ should be exempted by the dynamic prefix; only shared/orphan remains unused"
  end

  test "dynamic prefix with conditional expression still exempts all partials under the prefix" do
    # Mirrors PodRead's `render "shared/icons/\#{icon == 'copy' ? 'document_check' : 'check_circle'}"`
    write("app/views/shared/icons/_document_check.html.erb", "dc")
    write("app/views/shared/icons/_check_circle.html.erb", "cc")
    write("app/views/shared/icons/_unrelated.html.erb", "other")

    write(
      "app/views/shared/_clipboard_button.html.erb",
      '<%= render "shared/icons/#{icon == \'copy\' ? \'document_check\' : \'check_circle\'}", css_class: icon_class %>'
    )
    # Make the clipboard_button itself reachable
    write("app/views/pages/home.html.erb", '<%= render "shared/clipboard_button" %>')

    result = run_detector

    assert_empty result[:unused],
      "any partial whose name starts with the interpolation prefix `shared/icons/` must be exempt"
  end

  test "exempts all partials under a dynamic prefix expressed via partial: kwarg" do
    # Mirrors a future `broadcast_replace_to(..., partial: "shared/icons/#{name}")` site.
    # Today PodRead's only dynamic-interpolation sites use `render "..."` form,
    # but the detector must symmetrically handle the `partial:` kwarg form so
    # new Hotwire broadcast/render-to-string call sites don't silently orphan
    # every partial under their prefix.
    write("app/views/shared/icons/_check.html.erb", "check")
    write("app/views/shared/icons/_x_mark.html.erb", "x")
    # Plus a non-icon orphan that should still be flagged
    write("app/views/shared/_orphan.html.erb", "orphan")

    write(
      "app/models/episode.rb",
      <<~RUBY
        class Episode < ApplicationRecord
          after_update_commit do
            broadcast_replace_to(
              "episodes",
              partial: "shared/icons/\#{name}",
              locals: { name: "check" }
            )
          end
        end
      RUBY
    )

    # Top-level template exists but doesn't mention any icon partial.
    write("app/views/pages/home.html.erb", "<p>home</p>")

    result = run_detector(extra_source_roots: [ "app/models" ])

    assert_equal [ "shared/orphan" ], result[:unused],
      "all partials under shared/icons/ should be exempted by the dynamic partial: kwarg prefix; only shared/orphan remains unused"
  end

  # ---------------------------------------------------------------------------
  # Behavior 8: ERB comment stripping
  # ---------------------------------------------------------------------------

  test "ignores references that appear only inside ERB comments <%# ... %>" do
    write("app/views/shared/_only_in_comment.html.erb", "I'm only mentioned in a comment")
    write("app/views/shared/_real.html.erb", "real usage")

    # _only_in_comment is referenced only inside <%# %> — must be flagged unused.
    # _real is referenced in executable ERB — must be kept.
    write(
      "app/views/pages/home.html.erb",
      <<~ERB
        <%# Example usage: render "shared/only_in_comment" %>
        <%= render "shared/real" %>
      ERB
    )

    result = run_detector

    assert_includes result[:unused], "shared/only_in_comment",
      "a partial whose only reference is inside <%# %> should be flagged unused"
    refute_includes result[:unused], "shared/real"
  end

  # ---------------------------------------------------------------------------
  # Behavior 9: Transitive reachability (BFS to fixpoint)
  # ---------------------------------------------------------------------------

  test "transitive reachability: A rendered by top-level, A renders B, B renders C — all reachable" do
    write("app/views/chain/_a.html.erb", '<%= render "chain/b" %>')
    write("app/views/chain/_b.html.erb", '<%= render "chain/c" %>')
    write("app/views/chain/_c.html.erb", "leaf")

    write("app/views/pages/home.html.erb", '<%= render "chain/a" %>')

    result = run_detector

    assert_empty result[:unused], "A, B, C all reachable through transitive chain"
    assert_equal 3, result[:referenced]
  end

  test "transitive reachability: outer partial orphaned makes inner partials orphaned too" do
    # A renders B renders C, but NO top-level template renders A.
    write("app/views/chain/_a.html.erb", '<%= render "chain/b" %>')
    write("app/views/chain/_b.html.erb", '<%= render "chain/c" %>')
    write("app/views/chain/_c.html.erb", "leaf")

    # Top-level template exists but references NONE of the chain.
    write("app/views/pages/home.html.erb", "<p>hello</p>")

    result = run_detector

    # All three unreachable — deletion of A should correctly propagate.
    assert_equal %w[chain/a chain/b chain/c].sort, result[:unused].sort,
      "with no top-level caller of A, the entire A→B→C chain is unreachable"
  end

  # ---------------------------------------------------------------------------
  # Behavior 10: Cascading orphans — A→B, A has no caller, B has no other caller
  # ---------------------------------------------------------------------------

  test "cascading orphans: unused outer partial orphans its inner partials" do
    # A renders B. A has no caller. B has no other caller. Both unused.
    write("app/views/shared/_a.html.erb", '<%= render "shared/b" %>')
    write("app/views/shared/_b.html.erb", "inner")
    # Unrelated reachable partial to confirm detector isn't totally broken.
    write("app/views/shared/_used.html.erb", "used")

    write("app/views/pages/home.html.erb", '<%= render "shared/used" %>')

    result = run_detector

    assert_equal %w[shared/a shared/b].sort, result[:unused].sort,
      "both A and B should be unused; B's only ref is from A, which is itself unused"
    refute_includes result[:unused], "shared/used"
  end

  # ---------------------------------------------------------------------------
  # Return-shape sanity
  # ---------------------------------------------------------------------------

  test "result hash exposes :unused, :total, :referenced keys with consistent counts" do
    write("app/views/shared/_a.html.erb", "a")
    write("app/views/shared/_b.html.erb", "b")
    write("app/views/pages/home.html.erb", '<%= render "shared/a" %>')

    result = run_detector

    assert_kind_of Hash, result
    assert result.key?(:unused), "result must expose :unused key"
    assert result.key?(:total), "result must expose :total key"
    assert result.key?(:referenced), "result must expose :referenced key"
    assert_kind_of Array, result[:unused]
    assert_equal result[:total], result[:unused].length + result[:referenced],
      "total must equal unused + referenced"
  end
end
