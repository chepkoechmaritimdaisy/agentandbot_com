# Refactor Plan: Plug-and-Play Swarm Architecture

This document outlines the refactoring of the 'Agent' and 'Persona' data layers into a modular, fallback-oriented architecture.

## Goal
To create a "Composable Swarm" where components (Windmill, Telegram, Discord) can be added, removed, or upgraded, with automatic fallback to **Markdown Files** (`task.md`) when high-level services are unavailable.

## Proposed Changes

1.  **Capability-Based Context (`lib/governance_core/agents.ex`)**:
    - Implement a `Behaviours` system for Communication and Workflow.
    - Logic to pick the "best available" channel: `Windmill -> MQTT -> Markdown`.

2.  **Pluggable Adapters (`lib/governance_core/channels/`)**:
    - [NEW] `Channel` behaviour definition.
    - [NEW] Initial implementations: `Telegram`, `Email`, and the baseline `MarkdownFile`.

3.  **Graceful Task Engine (`lib/governance_core/task_engine.ex`)**:
    - Task delivery logic that attempts high-fidelity channels first.
    - Automatic "degradation" to Markdown if the primary channel fails or is disconnected.

4.  **Component-Aware Dashboard (`lib/governance_core_web/live/dashboard_live.ex`)**:
    - A "Service Grid" showing the status of each component.
    - Visual indicators for "Upgrading" (e.g., adding Discord) and "Fallback Active".

## Verification
- `mix compile` (Interface compliance check).
- Simulation: "Kill" the Windmill/Telegram mock and verify the system shifts to Markdown files.
- Manual: Verify UI reflects component swaps in real-time.
