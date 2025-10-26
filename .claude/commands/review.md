---
description: Review code changes using the code-reviewer subagent
argument-hint: [file-paths-or-description]
allowed-tools: Task
---

# Code Review Command

## Goal
Perform comprehensive code review of recent changes or specific files using the specialized code-reviewer subagent to ensure high standards of quality, security, and maintainability.

## Input
File paths or description of what to review: $ARGUMENTS

Usage examples:
```bash
/review
/review "recent changes"
/review app/models/user.rb
/review "user authentication module"
/review app/controllers/ test/models/
```

## Process

This command will invoke the code-reviewer subagent to:

1. **Analyze the scope** - Understand what code needs to be reviewed
2. **Examine recent changes** - Use git diff to see modifications if no specific files given
3. **Perform systematic review** - Check code quality, security, and maintainability
4. **Provide structured feedback** - Organize findings by priority level
5. **Suggest specific improvements** - Include Ruby examples of how to fix issues

## What the Code Reviewer Will Do

The code-reviewer subagent will:

### Initial Assessment
- **Run git diff** to identify recent changes (if no specific files provided)
- **Focus on modified files** and understand the scope of changes
- **Check commit context** to understand the purpose of changes

### Comprehensive Review
- **Code quality analysis** - Readability, naming, structure, DRY principles
- **Security audit** - Look for SQL injection, exposed secrets, input validation
- **Error handling review** - Proper exception handling and graceful degradation
- **Performance assessment** - N+1 queries, inefficient algorithms, memory usage
- **Testing evaluation** - Minitest coverage, meaningful test cases

## Expected Output

You'll receive a detailed review report with:

### 🚨 Critical Issues (Must Fix)
- SQL injection vulnerabilities
- Exposed API keys or secrets
- Breaking changes without migration
- Security authentication bypasses

### ⚠️ Warnings (Should Fix)
- N+1 query problems
- Missing error handling
- Performance bottlenecks
- Test coverage gaps

### 💡 Suggestions (Consider Improving)
- Variable naming improvements
- Code structure enhancements
- Better Ruby idioms usage
- Refactoring opportunities

### For Each Issue
- **Clear description** of the problem
- **Specific location** (file:line) where it occurs
- **Impact explanation** - why it matters
- **Concrete Ruby fix examples** - show exactly how to resolve
- **Prevention advice** - how to avoid similar issues

## When to Use This Command

- **After implementing new features** - Ensure quality before merging
- **Before creating pull requests** - Catch issues early
- **When refactoring Ruby/Rails code** - Verify improvements don't introduce problems
- **For security-sensitive changes** - Extra scrutiny for authentication, data handling
- **When onboarding new team members** - Educational code reviews
- **Before production deployments** - Final quality check

## Ruby-Specific Review Focus Areas

The reviewer will pay special attention to:

- **Rails security vulnerabilities** - SQL injection, mass assignment, XSS
- **ActiveRecord performance** - N+1 queries, inefficient database calls
- **Ruby error handling** - Proper rescue blocks and exception management
- **Code maintainability** - Clear naming, separation of concerns
- **Minitest test coverage** - Adequate testing of critical paths
- **Rails conventions** - Following Rails idioms and best practices

## Example Review Scenarios

### Rails Controller Review
```ruby
# Will catch issues like:
def show
  @user = User.find(params[:id])  # Missing error handling
  @posts = @user.posts.each { |p| p.comments.count }  # N+1 query
end
```

### Model Security Review  
```ruby
# Will catch issues like:
class User < ApplicationRecord
  def self.authenticate(email, password)
    where("email = '#{email}' AND password = '#{password}'").first  # SQL injection
  end
end
```

### Performance Review
```ruby
# Will catch issues like:
users.each do |user|
  user.update(last_seen: Time.now)  # N+1 updates
end
```

This command provides expert Ruby/Rails code review to help maintain high code quality standards and catch issues before they reach production.