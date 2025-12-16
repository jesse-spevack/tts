---
description: Generate engineering plan from PRD document
argument-hint: [prd-file-path]
allowed-tools: Read, Write, Grep, Glob, LS
---

# Generate Engineering Plan from PRD

## Goal
Create a detailed, step-by-step task list in Markdown format based on a Product Requirements Document (PRD). The task list will guide a developer through implementation.

## Input
PRD file path: $ARGUMENTS

## Process

### Phase 1: Analysis and High-Level Planning

1. **Read and analyze the PRD** at `$ARGUMENTS` or the context of our conversation.
   - Extract functional requirements, user stories, and acceptance criteria
   - Identify key features and technical requirements

2. **Assess current codebase state**
   - Review existing architecture patterns and conventions
   - Identify reusable components, utilities, and infrastructure
   - Find related files that may need modification
   - Understand testing patterns and framework usage

3. **Generate parent tasks**
   - Create main, high-level tasks (typically 3-8 tasks)
   - Ensure tasks align with PRD requirements
   - Consider logical implementation order

4. **Create initial task file**
   - Generate file at `tasks/tasks-[prd-file-name].md`
   - Include parent tasks without sub-tasks
   - Add placeholder for relevant files section

5. **Present to user and wait**
   - Show the generated high-level tasks
   - Ask: "I have generated the high-level tasks based on the PRD. Ready to generate the sub-tasks? Respond with 'Go' to proceed."
   - STOP and wait for user confirmation

### Phase 2: Detailed Task Breakdown (After User Confirms with "Go")

6. **Generate sub-tasks**
   - Break each parent task into actionable sub-tasks
   - Ensure sub-tasks are specific and implementable
   - Consider existing codebase patterns
   - Include testing tasks where appropriate

7. **Identify relevant files**
   - List files to be created or modified
   - Include corresponding test files
   - Add brief descriptions for each file's purpose

8. **Update the task file** with:
   - Complete parent tasks with sub-tasks
   - Relevant files section with descriptions
   - Notes about testing approach and commands

## Output Format

The task list must follow this structure:

```markdown
# Tasks for [Feature Name from PRD]

## Tasks

- [ ] 1.0 [Parent Task Title]
  - [ ] 1.1 [Specific sub-task]
  - [ ] 1.2 [Specific sub-task]
  - [ ] 1.3 [Specific sub-task]
  
- [ ] 2.0 [Parent Task Title]
  - [ ] 2.1 [Specific sub-task]
  - [ ] 2.2 [Specific sub-task]
  
- [ ] 3.0 [Parent Task Title]
  - [ ] 3.1 [Specific sub-task]
  
- [ ] 4.0 Testing and Documentation
  - [ ] 4.1 Write unit tests for new components
  - [ ] 4.2 Write integration tests for API endpoints
  - [ ] 4.3 Update documentation
```

## Target Audience

Assume the reader is a **junior developer** who needs clear, actionable tasks with awareness of existing codebase context.

## Important Notes

- Tasks should be concrete and implementable
- Consider existing patterns but don't be constrained by them
- Include testing as part of the implementation process
- Ensure logical task ordering for smooth implementation
