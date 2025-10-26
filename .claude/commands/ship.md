---
description: Add, commit, and push changes with semantic commit message
argument-hint: [optional-commit-message]
allowed-tools: Bash, Read, Glob
---

# Ship Changes Command

## Goal
Systematically add all modified and new files to git, create a semantic commit with a clear message, and push to origin. Includes intelligent checks for files that shouldn't be committed and opportunities for separate commits.

## Input
Optional commit message: $ARGUMENTS

Usage examples:
```bash
/ship
/ship "add user authentication feature"
/ship "fix: resolve login validation bug"
```

## Process

### Phase 1: Git Status Analysis

1. **Check git status** - Identify all modified, new, and deleted files
2. **Analyze file types** - Look for files that typically shouldn't be committed:
   - Temporary files (*.tmp, *.log, *.swp)
   - Build artifacts (dist/, build/, node_modules/)
   - Environment files (.env, .env.local)
   - IDE files (.vscode/, .idea/)
   - OS files (.DS_Store, Thumbs.db)
   - Backup files (*.bak, *~)

3. **Check for .gitignore coverage** - Verify suspicious files aren't already ignored

### Phase 2: User Consultation

4. **Ask about questionable files** - If any files seem like they shouldn't be committed:
   ```
   Found files that may not belong in version control:
   - .env.local (contains environment variables)
   - debug.log (temporary log file)
   - .DS_Store (OS metadata file)
   
   Should these be committed? (y/n)
   If no, would you like me to add them to .gitignore? (y/n)
   ```

5. **Ask about commit grouping** - If changes span multiple areas:
   ```
   Changes detected across multiple areas:
   - Authentication: app/models/user.rb, app/controllers/sessions_controller.rb
   - Tests: test/models/user_test.rb, test/controllers/sessions_test_rb
   - Documentation: README.md, docs/auth.md
   
   Would you prefer separate commits for these groups? (y/n)
   ```

### Phase 3: Code Quality Check

6. **Run rubocop auto-fix** before committing:
   ```bash
   rubocop -A
   ```
   - Automatically fixes style issues
   - Ensures consistent code style
   - Run tests after to verify fixes don't break functionality

### Phase 4: Commit Creation

7. **Generate semantic commit message** if not provided:
   - Analyze the nature of changes (new features, bug fixes, refactoring, etc.)
   - Use semantic commit format: `type(scope): description`
   - Common types: feat, fix, docs, style, refactor, test, chore
   - Keep description under 50 characters
   - Use imperative mood ("add" not "added")

8. **Stage all approved files**:
   ```bash
   git add [files]
   ```

9. **Create commit**:
   ```bash
   git commit -m "feat(auth): add user authentication system"
   ```

### Phase 5: Push to Remote

10. **Check remote tracking** - Ensure current branch tracks a remote
11. **Push to origin**:
   ```bash
   git push origin [current-branch]
   ```

## Semantic Commit Types

- **feat**: New feature for the user
- **fix**: Bug fix for the user
- **docs**: Documentation changes
- **style**: Code formatting, missing semicolons, etc.
- **refactor**: Code refactoring without changing functionality
- **test**: Adding or updating tests
- **chore**: Maintenance tasks, dependency updates

## Example Commit Messages

```bash
feat(auth): add user login and registration
fix(validation): resolve email format validation bug  
docs(readme): update installation instructions
test(models): add comprehensive user model tests
refactor(controllers): extract common authentication logic
chore(deps): update rails to version 7.1
```

## Safety Checks

- **Verify clean working directory** after commit
- **Confirm push success** to remote repository
- **Handle push conflicts** gracefully with clear instructions
- **Backup strategy** - commits are local before push, easy to amend if needed

## Error Handling

- **Merge conflicts** - Provide clear instructions to resolve
- **Push rejected** - Guide user through pull and rebase if needed
- **Unstaged changes** - Ensure all intended changes are included
- **Empty commits** - Warn if no changes to commit

## Output

Provides clear status throughout:
- Files being added to staging
- Generated or provided commit message
- Commit SHA for reference
- Push confirmation with remote branch info
- Any warnings or recommendations

This command streamlines the entire git workflow from unstaged changes to pushed commits while maintaining good git hygiene and semantic commit standards.