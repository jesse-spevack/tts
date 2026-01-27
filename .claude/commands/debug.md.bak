---
description: Debug errors and problems using the debugger subagent
argument-hint: [error-message-or-problem-description]
allowed-tools: Task
---

# Debug Command

## Goal
Investigate and resolve errors, test failures, or unexpected behavior by invoking the specialized debugger subagent with the provided problem description.

## Input
Error message or problem description: $ARGUMENTS

Usage examples:
```bash
/debug "TypeError: Cannot read property 'name' of undefined"
/debug "Tests are failing in user authentication module"
/debug "Application crashes when processing large files"
/debug "API returns 500 error on POST requests"
```

## Process

This command will invoke the debugger subagent with your problem description, providing it with the context needed to:

1. **Analyze the issue** - Parse error messages, understand the problem scope
2. **Investigate systematically** - Search for relevant code, check recent changes
3. **Form hypotheses** - Create theories about potential causes
4. **Isolate the root cause** - Pinpoint the actual source of the problem  
5. **Implement a fix** - Make targeted changes to resolve the issue
6. **Verify the solution** - Ensure the fix works and doesn't break other functionality
7. **Provide prevention advice** - Suggest ways to avoid similar issues

## What the Debugger Will Do

The debugger subagent will receive your problem description and:

- **Capture full context** - Examine error messages, stack traces, logs
- **Search the codebase** - Find relevant files and recent changes
- **Reproduce the issue** - Understand how to recreate the problem
- **Debug systematically** - Use logging, testing, and analysis tools
- **Fix the root cause** - Address the underlying issue, not just symptoms
- **Test the solution** - Verify the fix resolves the problem completely

## Expected Output

You'll receive a comprehensive debugging report including:

- **Root cause explanation** - What actually caused the problem
- **Evidence and analysis** - How the debugger determined the cause  
- **Specific fix implemented** - Exact code changes made
- **Verification results** - Proof that the solution works
- **Prevention recommendations** - How to avoid this type of issue in the future

## When to Use This Command

- When you encounter error messages or exceptions
- When tests are failing unexpectedly  
- When application behavior doesn't match expectations
- When performance issues or crashes occur
- When integration problems arise between components
- When you need systematic investigation of any technical problem

This command provides expert debugging assistance for any technical issue you're facing.