# Refactoring Tasks - Technical Debt Elimination

This document contains three high-impact refactoring tasks to improve maintainability and reduce technical debt in the Very Normal TTS Rails application.

Each task includes a complete prompt that can be delegated to a coding agent for investigation and implementation.

---

## Task 1: Extract Duplicated Result Pattern

**Priority:** HIGHEST
**Impact:** Eliminates ~150-200 lines of duplicated code
**Estimated Time:** 2-3 hours
**Difficulty:** Low

### Prompt for Coding Agent

```
You are an expert Ruby on Rails engineer working on the Very Normal TTS application.

CONTEXT:
The codebase currently has 7 service classes that each define their own identical Result class:
- app/services/create_url_episode.rb
- app/services/create_paste_episode.rb
- app/services/create_file_episode.rb
- app/services/checks_episode_creation_permission.rb
- app/services/processes_with_llm.rb
- app/services/fetches_url.rb
- app/services/extracts_article.rb

Each Result class follows the same pattern:
- Factory methods: .success() and .failure()
- Predicate methods: success? and failure?
- Attribute readers for return values and errors

This duplication makes it harder to:
1. Add monitoring/logging hooks to all results
2. Extend Result functionality (e.g., add .tap, .bind for functional composition)
3. Maintain consistency across services

YOUR TASK:
Investigate and create a detailed implementation plan to extract the Result pattern into a shared base class or concern.

REQUIREMENTS:
1. Analyze all 7 existing Result class implementations and identify:
   - Common patterns across all implementations
   - Differences in attributes (episode, error, remaining, html, text, title, author, description, content, etc.)
   - How each Result is used by controllers and tests

2. Design a solution that:
   - Creates a single, reusable ServiceResult base class
   - Supports arbitrary attributes (different services return different data)
   - Maintains backward compatibility with existing controller code
   - Preserves the existing API (success?, failure?, success, failure methods)
   - Is extensible for future enhancements (logging, monitoring, etc.)

3. Create an implementation plan that includes:
   - Where to place the new ServiceResult class (app/services/concerns/ or lib/?)
   - Exact code for the ServiceResult class
   - Migration strategy: which services to update in what order
   - How to handle differences in Result attributes across services
   - Test strategy to ensure no regressions
   - List of files that need to be modified

4. Consider these design options and recommend the best approach:
   - Option A: Simple inheritance with dynamic attributes
   - Option B: Using Struct with custom methods
   - Option C: Using dry-monads gem (external dependency)
   - Option D: Using a Ruby module/concern

5. Identify risks and mitigation strategies:
   - Breaking changes to existing code
   - Test failures
   - Performance implications
   - Developer ergonomics

DELIVERABLE:
Provide a detailed markdown document with:
1. Analysis of current Result implementations (with code examples)
2. Recommended solution design with code examples
3. Step-by-step implementation plan
4. Testing strategy
5. Risk assessment
6. Estimated time to implement each step

Do NOT implement the changes yet - this is a planning phase only.
```

---

## Task 2: Centralize Configuration Constants

**Priority:** HIGH
**Impact:** Makes business rule changes 10x easier, eliminates scattered magic numbers
**Estimated Time:** 4-6 hours
**Difficulty:** Medium

### Prompt for Coding Agent

```
You are an expert Ruby on Rails engineer working on the Very Normal TTS application.

CONTEXT:
Business logic constants are currently scattered across 10+ files with no single source of truth:

1. Character limits for user tiers:
   - app/services/validates_episode_submission.rb: MAX_CHARACTERS_FREE = 15_000
   - app/services/validates_episode_submission.rb: MAX_CHARACTERS_PREMIUM = 50_000
   - app/services/processes_with_llm.rb: MAX_INPUT_CHARS = 100_000

2. Content length constraints:
   - app/services/extracts_article.rb: MIN_CONTENT_LENGTH = 100
   - app/services/create_paste_episode.rb: MINIMUM_LENGTH = 100 (DUPLICATE!)
   - app/services/extracts_article.rb: MAX_HTML_BYTES = 10 * 1024 * 1024
   - app/services/fetches_url.rb: MAX_CONTENT_LENGTH = 10 * 1024 * 1024 (DUPLICATE!)

3. User tier limits:
   - app/services/checks_episode_creation_permission.rb: FREE_MONTHLY_LIMIT = 2

4. Voice configuration:
   - app/models/voice.rb: STANDARD and CHIRP voice arrays
   - app/models/voice.rb: for_tier method with hardcoded tier logic

5. LLM constraints:
   - app/services/processes_with_llm.rb: MAX_TITLE_LENGTH = 255
   - app/services/processes_with_llm.rb: MAX_AUTHOR_LENGTH = 255
   - app/services/processes_with_llm.rb: MAX_DESCRIPTION_LENGTH = 1000

This makes it difficult to:
- Change business rules (must hunt through multiple files)
- Understand tier limitations at a glance
- Avoid bugs from duplicate/inconsistent constants
- Perform A/B testing on limits

YOUR TASK:
Investigate and create a detailed implementation plan to centralize all configuration constants into a single, well-organized location.

REQUIREMENTS:
1. Conduct a comprehensive audit:
   - Find ALL constants related to limits, tiers, and business rules
   - Use grep/search to find: MAX_*, MIN_*, LIMIT, tier-related logic, voice configuration
   - Document current location, value, and usage of each constant
   - Identify duplicates and inconsistencies

2. Design a centralized configuration system:
   - Decide on location: app/models/app_config.rb, config/application.rb, or lib/config/?
   - Group related constants logically (tier limits, content limits, LLM limits, etc.)
   - Create helper methods for common patterns (e.g., character_limit_for(user))
   - Consider whether to use: plain Ruby class, Rails.application.config, or Settings gem

3. Plan the migration:
   - Order services by dependency (which to update first)
   - Identify services that reference multiple constants
   - Plan how to handle tier-based logic (case statements -> helper methods)
   - Consider deprecation strategy if needed

4. Address the duplicate constants:
   - MIN_CONTENT_LENGTH (100) vs MINIMUM_LENGTH (100)
   - MAX_HTML_BYTES (10MB) vs MAX_CONTENT_LENGTH (10MB)
   - Decide on canonical names and values

5. Plan voice configuration refactoring:
   - Should Voice model still contain tier logic?
   - How to make Voice a pure data class?
   - Where should voice-tier mapping live?

6. Consider these design options:
   - Option A: Simple Ruby class with constants and class methods
   - Option B: Rails.application.config with nested hashes
   - Option C: Config gem (e.g., config, rails-settings-cached)
   - Option D: YAML configuration files

7. Testing strategy:
   - How to ensure no constants are missed?
   - How to verify all references are updated?
   - Test that business logic remains unchanged

DELIVERABLE:
Provide a detailed markdown document with:
1. Complete audit of all constants (table format: name, location, value, usage count)
2. List of duplicates and recommended resolution
3. Recommended configuration system design with code examples
4. Proposed AppConfig class structure (or alternative)
5. Step-by-step migration plan with file-by-file changes
6. Before/after code examples for key services
7. Testing strategy
8. Risk assessment
9. Estimated time per step

Do NOT implement the changes yet - this is a planning phase only.
```

---

## Task 3: Consolidate Validation Logic

**Priority:** MEDIUM-HIGH
**Impact:** Strengthens data integrity, eliminates duplication, improves testability
**Estimated Time:** 3-4 hours
**Difficulty:** Medium

### Prompt for Coding Agent

```
You are an expert Ruby on Rails engineer working on the Very Normal TTS application.

CONTEXT:
Content validation logic is currently scattered across multiple services instead of being centralized in models or dedicated validators:

1. app/services/create_paste_episode.rb:
   - Validates text is not blank
   - Validates text >= 100 characters (MINIMUM_LENGTH constant)
   - Validates text doesn't exceed user tier limit
   - Returns different error messages for each case

2. app/services/create_file_episode.rb:
   - Validates content is not blank
   - Validates content doesn't exceed user tier limit
   - Nearly identical to create_paste_episode validation

3. app/services/process_url_episode.rb:
   - Checks character limit after article extraction
   - Raises ProcessingError if content too long for tier
   - Different error handling than create services

4. app/services/extracts_article.rb:
   - MIN_CONTENT_LENGTH = 100 (duplicate of MINIMUM_LENGTH above)
   - Validates extracted content >= 100 characters
   - Returns Result.failure with error message

5. app/models/episode.rb:
   - Has SOME validations (title, author, description presence/length)
   - Does NOT have content length validation
   - Does NOT have tier-based validation

This scattered validation causes:
- Duplicate validation logic in 4+ places
- Inconsistent error messages
- Weaker data integrity (can create invalid episodes if service validations bypassed)
- Harder to test (must test validation in multiple services)
- Violates Rails conventions (validations should be in models)

YOUR TASK:
Investigate and create a detailed implementation plan to consolidate validation logic into models or dedicated validator objects.

REQUIREMENTS:
1. Analyze current validation patterns:
   - Document all validation logic across services (location, conditions, error messages)
   - Identify duplicates and near-duplicates
   - Understand why validation is in services vs models
   - Review how controllers/services currently handle validation errors

2. Evaluate consolidation approaches:

   Option A: Move to Episode model validations
   - Add custom validations to Episode model
   - Use conditional validations (if: -> { ... })
   - Handle user tier limits in model validation

   Option B: Create dedicated validator objects
   - EpisodeContentValidator class
   - Use ActiveModel::Validations
   - Call from services before creating episode

   Option C: Hybrid approach
   - Basic validations in Episode model
   - Complex tier-based validations in validator objects

   Option D: Form objects
   - EpisodeCreationForm that wraps validation
   - Services use form objects instead of direct model creation

3. Address these challenges:
   - Episode validation needs access to User (for tier limits)
   - Different sources: url, paste, file may have different validation needs
   - Some validations happen before episode exists (in create services)
   - Some validations happen after extraction (in process services)
   - Error messages must remain user-friendly

4. Plan the migration:
   - Which validation to move first (lowest risk)
   - How to handle the dependency on AppConfig constants (if Task 2 is done)
   - How to maintain backward compatibility during transition
   - Whether to deprecate old service-level validations or remove immediately

5. Consider Rails best practices:
   - ActiveModel::Validations vs custom validate methods
   - Context-specific validations (on: :create vs on: :update)
   - Should validations be on Episode or on a virtual/form object?
   - How to handle validations that require external data (user tier)

6. Testing strategy:
   - Model validation tests vs service integration tests
   - How to test tier-based validations
   - Ensure all edge cases are covered
   - Test that error messages are user-friendly

7. Analyze impact on existing code:
   - How many controller actions will need updates?
   - How many service tests will need updates?
   - Will this change the service Result pattern usage?

DELIVERABLE:
Provide a detailed markdown document with:
1. Complete audit of validation logic (table: location, validation type, error message)
2. Analysis of duplicate validations
3. Recommended consolidation approach with justification
4. Detailed design with code examples:
   - New validator class(es) or model validations
   - How services will use the new validation
   - How controllers will handle validation errors
5. Step-by-step migration plan
6. Before/after code examples for each affected service
7. List of all files that need modification
8. Testing strategy with test examples
9. Risk assessment
10. Consideration of how this interacts with Task 1 (Result pattern) and Task 2 (Config)
11. Estimated time per step

Do NOT implement the changes yet - this is a planning phase only.
```

---

## Implementation Order

**Recommended sequence:**

1. **Task 1 (Result Pattern)** - Independent, lowest risk, sets foundation
2. **Task 2 (Config)** - Required for Task 3, medium risk
3. **Task 3 (Validation)** - Depends on Task 2, highest complexity

**Alternatively, for parallel execution:**
- Task 1 and Task 2 can be done in parallel (independent)
- Task 3 should wait for Task 2 completion (depends on centralized config)

---

## Success Criteria

Each task is successful when:
1. ✅ Detailed investigation plan is complete
2. ✅ All current usages are documented
3. ✅ Solution design is clear with code examples
4. ✅ Migration plan is step-by-step and actionable
5. ✅ Risks are identified with mitigation strategies
6. ✅ Testing strategy is comprehensive
7. ✅ Time estimates are realistic
8. ✅ The plan is ready for implementation by any Rails developer

---

## Notes

- All three tasks were identified through comprehensive codebase review
- Combined, these changes will eliminate 300+ lines of duplicated code
- Long-term maintainability improvement is estimated at 10x for business rule changes
- Current codebase is well-structured; these are optimization opportunities, not critical bugs
- The application follows Rails conventions; these tasks will strengthen that alignment

---

## References

**Key Files to Review:**

Task 1:
- app/services/create_*.rb (3 files)
- app/services/checks_episode_creation_permission.rb
- app/services/processes_with_llm.rb
- app/services/fetches_url.rb
- app/services/extracts_article.rb

Task 2:
- app/services/validates_episode_submission.rb
- app/services/processes_with_llm.rb
- app/services/extracts_article.rb
- app/services/fetches_url.rb
- app/services/create_paste_episode.rb
- app/services/checks_episode_creation_permission.rb
- app/models/voice.rb

Task 3:
- app/models/episode.rb
- app/services/create_paste_episode.rb
- app/services/create_file_episode.rb
- app/services/process_url_episode.rb
- app/services/extracts_article.rb
- app/controllers/episodes_controller.rb

**Architecture Context:**
- Service-oriented architecture (47 services)
- All services follow `.call` pattern
- Controllers delegate to services
- Background jobs (Solid Queue) process episodes asynchronously
- Test coverage ~1.5:1 (10,466 lines test / 6,704 lines app)
