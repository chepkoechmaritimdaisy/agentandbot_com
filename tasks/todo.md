# TODO — agentandbot.com

## Dual Flow Architecture ✅ (2026-02-22)

### Completed
- [x] Create implementation plan
- [x] Create Agent Detail LiveView (`/agents/:id`)
- [x] Create Agent Create LiveView (`/agents/new`)
- [x] Create Dashboard LiveView (`/dashboard`)
- [x] Create API: `AgentController` (`/api/agents`)
- [x] Create API: `TaskController` (`/api/tasks`)
- [x] Update router (12 routes)
- [x] Update shared nav (Dashboard link)
- [x] Update agent discovery (ABL.ONE/1.0)
- [x] Add CSS (~600 lines)
- [x] Update Screen Registry (design skill)
- [x] `mix compile` — passed ✅

### Outstanding
- [ ] DRY refactor: extract shared agent data to `GovernanceCore.Agents` context module
- [ ] Start PostgreSQL and run `mix test`
- [ ] Browser verification of all 7 pages
- [ ] Update Stitch screens via MCP (needs IDE restart)
- [ ] Update `README.md`

### Review
- **Compilation**: Clean, zero errors
- **Design Compliance**: All styles use Design System v1 tokens
- **Architecture**: Dual Flow (Human + Machine) fully routed
- **Gap**: Agent data duplicated in 3 files — needs DRY refactor
