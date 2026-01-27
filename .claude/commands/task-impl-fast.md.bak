---
description: Implement tasks from a task list
argument-hint: [task-list-file]
allowed-tools: Read, Write, Edit, MultiEdit, Bash, Grep, Glob, LS, TodoWrite
---

# Task Implementation Command

## Goal
Systematically implement tasks from a markdown task list file, following strict protocols for subtask completion, testing, committing.

## Input
Task list file path: $ARGUMENTS

Usage examples:
```bash
/task-implement tasks/tasks-user-auth.md
/task-implement tasks/tasks-payment-system.md
```

## Process

### Phase 1: Task List Analysis

1. **Read the task list file** from `$ARGUMENTS`
2. **Identify the next uncompleted subtask** (first `[ ]` item)
3. **Load relevant context** from the task description and parent task
4. **Update TodoWrite** to track current progress

### Phase 2: Single Subtask Implementation

5. **Implement ONLY the current subtask**
   - Focus exclusively on the specific subtask requirements
   - Do not start any other subtasks
   - Follow existing code patterns and conventions
   - Create or modify files as needed

6. **Mark subtask as completed**
   - Change `[ ]` to `[x]` in the task list file
   - Update the task list file immediately after completion

### Phase 3: Parent Task Completion Check

7. **Check if all subtasks under parent are complete**
   If YES, execute the completion protocol:

   a. **Run the full test suite**

   b. **Only if all tests pass**: Stage changes
      ```bash
      git add .
      ```

   c. **Clean up temporary files and code**
      - Remove debug statements
      - Delete temporary test files
      - Clean up commented code

   d. **Create semantic commit** with multi-line format:
      ```bash
      git commit -m "feat: add payment validation logic" \
                 -m "- Validates card type and expiry" \
                 -m "- Adds unit tests for edge cases" \
                 -m "- Implements error handling" \
                 -m "Related to Task 2.0 in PRD"
      ```

   e. **Mark parent task as completed** `[x]`

### Phase 4: Update Documentation

8. **Update "Relevant Files" section**
   - Add newly created files with descriptions
   - Update descriptions for modified files
   - Ensure all touched files are documented

9. **Save the updated task list**

### Phase 5: Continue or Complete

10. **If more subtasks remain**: Return to Phase 2
11. **If all tasks complete**: Provide final summary

Always use multi-line commits with `-m` flags:
```bash
git commit -m "type: brief description" \
           -m "- Detail 1" \
           -m "- Detail 2" \
           -m "Related to Task X.X in [context]"
```

Types: feat, fix, docs, style, refactor, test, chore

## Task List Format Expected

```markdown
## Relevant Files
- `app/models/user.rb` - User model with authentication
- `test/models/user_test.rb` - User model tests

## Tasks
- [ ] 1.0 Implement user authentication
  - [x] 1.1 Create user model
  - [ ] 1.2 Add password encryption
  - [ ] 1.3 Implement login method
  
- [ ] 2.0 Add authorization
  - [ ] 2.1 Create role model
  - [ ] 2.2 Add role associations
```

## Error Handling

- **Test failures**: Fix issues before committing
- **Merge conflicts**: Resolve before continuing
- **Missing dependencies**: Install required packages
- **Unclear requirements**: Ask user for clarification

## Progress Tracking

Maintain clear status throughout:
- Current subtask being worked on
- Files created or modified
- Test results after parent completion
- Commit messages created
- Clear stopping points for user approval

## Important Notes

- **Discipline is key**: Never skip ahead or batch subtasks
- **Testing is mandatory**: No commits without passing tests
- **User control maintained**: Always wait for permission
- **Clean commits**: Remove temporary code before committing
- **Semantic commits**: Use conventional commit format

This command ensures methodical, controlled task implementation with clear checkpoints and quality gates at every step.
