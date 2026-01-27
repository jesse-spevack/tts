---
description: Orchestrate TDD implementation of engineering plan tasks
argument-hint: [task-number] [eng-plan-file]
allowed-tools: Read, Task, TodoWrite, Bash
---

# TDD Implementation Orchestrator

## Goal
Take a specific task from an engineering plan and implement it using Test-Driven Development (TDD) by orchestrating the tdd-test-writer and tdd-implementer agents in proper sequence.

## Input
- Task number: First part of $ARGUMENTS (e.g., "1.2" or "3.1")
- Engineering plan file: Second part of $ARGUMENTS (e.g., "tasks/tasks-user-auth.md")

Usage: `/tdd-implement 1.2 tasks/tasks-user-auth.md`

## Process

### Phase 1: Task Analysis and Setup

1. **Read the engineering plan** from the specified file
2. **Extract the specific task** using the task number provided
3. **Create a todo list** to track the TDD implementation cycle
4. **Verify test setup** - ensure test files and structure are ready

### Phase 2: TDD Cycle Orchestration

Implement the classic TDD Red-Green-Refactor cycle:

#### RED Phase (Test First)
5. **Invoke tdd-test-writer agent** to:
   - Understand the task requirements
   - Write a failing test for the next piece of functionality
   - Run the test to confirm it fails appropriately
   - Report what needs to be implemented

#### GREEN Phase (Make It Pass)  
6. **Invoke tdd-implementer agent** to:
   - Analyze the failing test
   - Search for existing code to reuse
   - Write minimal implementation to make test pass
   - Verify the test now passes
   - Report completion

#### REFACTOR Phase (Clean Up)
7. **Invoke tdd-refactorer agent** to:
   - Identify code smells in the new implementation
   - Apply refactoring patterns while keeping tests green
   - Run tests after each refactoring step
   - Report improvements made

### Phase 3: Cycle Management

8. **Determine if task is complete** - check if all acceptance criteria are met
9. **If not complete**: Return to RED phase for next test case
10. **If complete**: Mark task as done and summarize implementation

## Todo List Structure

The orchestrator will create and maintain todos like:

- [ ] 1.0 Analyze task requirements from eng plan
- [ ] 2.0 RED: Write failing test for [specific functionality]  
- [ ] 3.0 GREEN: Implement code to make test pass
- [ ] 4.0 REFACTOR: Clean up implementation if needed
- [ ] 5.0 Run full test suite to ensure no regressions
- [ ] 6.0 Determine if more test cases needed
- [ ] 7.0 Complete task implementation

## Agent Coordination

### Calling tdd-test-writer
```
Use the tdd-test-writer subagent to create a failing test for: [specific requirement from the task]
```

### Calling tdd-implementer  
```
Use the tdd-implementer subagent to make this failing test pass: [test description]
```

### Calling tdd-refactorer
```
Use the tdd-refactorer subagent to improve code structure while keeping tests green for: [implementation that was just created]
```

### Between Cycles
- Update todos to reflect current progress
- Run tests to verify current state
- Analyze if the task requirements are fully satisfied
- Decide whether to continue with more test cases or move to completion

## Success Criteria

The task is considered complete when:
- All acceptance criteria from the eng plan task are covered by tests
- All tests pass
- Implementation follows existing codebase patterns
- No regressions in the existing test suite
- Code is clean and minimal (only what tests require)

## Output

At completion, provide:
- Summary of what was implemented
- List of files created or modified
- Test coverage achieved
- Any notes for the next task in the sequence

## Important Notes

- **Maintain strict TDD discipline** - never let implementer work without a failing test
- **One test at a time** - don't overwhelm with multiple failing tests
- **Trust the agents** - let them do their specialized work
- **Track progress** - keep todos updated throughout the process
- **Stop when done** - don't over-implement beyond task requirements
- **Complete the cycle** - always include refactoring phase after implementation

This command orchestrates true TDD trio programming between the test writer, implementer, and refactorer, ensuring proper Red-Green-Refactor flow while implementing engineering plan tasks systematically.