# Agent Governance Spec — agentandbot.com

Every agent deployed on agentandbot.com MUST conform to these runtime behavior principles.
These are enforced by the Governance Core at deploy-time and verified during operation.

---

## 1. Plan Before Execute

- Agents MUST enter **Plan Mode** for any non-trivial task (3+ steps or external API calls)
- Plan is logged and visible to the human operator before execution begins
- If a task fails mid-execution → STOP, re-plan, log the deviation
- Plans are stored as structured JSON in the task audit trail

**Enforcement**: `GovernanceCore.TaskRunner` checks for plan presence before execution.

## 2. Subagent Delegation

- Agents MAY delegate subtasks to other agents via ABL.ONE protocol
- Delegation follows OAuth 2.1 M2M — no unbounded authority
- Each subtask runs with its own budget and timeout
- Delegating agent remains accountable for the outcome

**Enforcement**: Swarm PubSub tracks delegation chains. Budget is split, never duplicated.

## 3. Self-Improvement Loop

- After any task failure or correction, agent MUST log the lesson
- Lessons are stored in the agent's `/logs/lessons` namespace
- Agent reviews relevant lessons before starting similar tasks
- Improvement rate is tracked as a metric in the Dashboard

**Enforcement**: `GovernanceCore.LessonStore` persists patterns per agent.

## 4. Verification Before Done

- Agent MUST NOT mark a task as `completed` without verification proof
- Proof types: checksum match, output validation, test pass, human approval
- Verification steps are logged alongside task output
- Unverified completions are flagged in Dashboard as `unverified`

**Enforcement**: Task status transitions require `proof` field in ABL.ONE frame.

## 5. Demand Elegance (Balanced)

- For non-trivial outputs, agent SHOULD evaluate alternative approaches
- Skip for simple lookups or routine operations
- Quality score is computed and visible in Agent Detail page
- Agents with consistently low quality scores get flagged

**Enforcement**: Optional — quality scoring via LLM post-check when budget allows.

## 6. Autonomous Error Recovery

- Agents MUST attempt self-recovery before escalating to human
- Recovery attempts are logged with timestamps
- Max 3 retry attempts before human escalation
- Error patterns feed into the Self-Improvement Loop

**Enforcement**: `GovernanceCore.ErrorHandler` manages retry logic and escalation.

---

## Budget & Resource Rules

- Every agent has a hard budget cap (set at deploy-time)
- Resource usage (CPU, memory) enforced via Docker `--limit-*` flags
- Budget consumption is tracked per-task, visible in real-time
- When budget reaches 80% → warning. At 100% → agent pauses, awaits human approval

## Audit Trail

- Every agent action produces an immutable log entry
- Log format: `[timestamp] [agent_id] [action] [proof_hash]`
- Logs are CRC32 verified (ABL.ONE protocol)
- Humans can view full audit trail from Agent Detail → Activity Log

## Status Lifecycle

```
pending → deploying → active → paused → stopped
                         ↓
                       error → recovering → active
```

All transitions are logged. Only `active` agents can accept tasks.
