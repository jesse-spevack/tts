# Test Guidelines for Claude

## Test Quality Principles

### Write Tests First
- When implementing a new class or feature, write tests BEFORE writing the implementation
- Tests should define the expected behavior and API

### Focus on High-Value Tests
Ask yourself:
- Does this test verify business logic or critical behavior?
- Would removing this test make the codebase less safe?
- Is this testing our code or testing Ruby/library behavior?

### Avoid Low-Value Tests
Remove tests that:
- Test trivial getters/setters
- Test Ruby standard library behavior (e.g., JSON parsing)
- Test presence/absence of optional fields without logic
- Simply count items without testing content
- Cover edge cases that don't matter in practice

### Keep Tests Simple and Readable
- Extract test data into private helper methods
- Use descriptive helper methods to reduce complexity (e.g., `parse_channel(xml)` instead of inline REXML parsing)
- Avoid long setup methods - break data into focused helper methods
- Keep test methods under 20 lines when possible

### Mocking Guidelines
- Only mock external dependencies (APIs, databases, file systems)
- Don't mock for the sake of mocking
- If a mock isn't being used, remove it
- Mock methods should accept parameters even if unused (use `**` for keyword args)
- Consider: Does removing this mock simplify the test without losing value?

### RuboCop Compliance
- All tests must pass `rake rubocop`
- For test files:
  - Methods under 20 lines
  - AbcSize under 25
  - Class length under 150 lines
- If hitting limits, refactor by:
  1. Extracting helper methods
  2. Removing low-value tests
  3. Simplifying test data

### Example: Good vs Bad

**Bad:**
```ruby
def test_load_returns_episodes_from_gcs
  @mock_uploader.manifest_content = complex_json
  episodes = @manifest.load
  assert_equal 1, episodes.length  # Just testing JSON.parse
end
```

**Good:**
```ruby
def test_add_episode_sorts_by_published_at_newest_first
  @manifest.add_episode(old_episode)
  @manifest.add_episode(new_episode)
  assert_equal "New Episode", @manifest.episodes[0]["title"]  # Tests business logic
end
```

## Quick Checklist Before Committing Tests

- [ ] Tests are written first (TDD)
- [ ] All tests verify business logic, not library behavior
- [ ] No unused mocks or test data
- [ ] Helper methods used to reduce complexity
- [ ] `rake test` passes
- [ ] `rake rubocop` passes with no offenses
- [ ] Each test has clear value - would removing it make codebase less safe?
