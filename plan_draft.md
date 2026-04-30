1. **Update Dependencies in `mix.exs`**
   - Read `governance_core/mix.exs`.
   - Add `{:stream_data, "~> 0.6"}` to the `deps` list to enable Fuzzing, complying with the requirement that it hasn't reached 1.0 yet.
   - Use `read_file` to verify the addition.

2. **Implement UMP Fuzzer (`GovernanceCore.Protocols.Fuzzer`)**
   - Create `governance_core/lib/governance_core/protocols/fuzzer.ex`.
   - Implement Fuzzer logic: A GenServer that runs continuously (using `Process.send_after/3` on a 5-minute interval).
   - During the interval, generate random binary data using `StreamData.binary()` and `Enum.take(generator, 100)`.
   - Feed the generated binaries to `GovernanceCore.Protocols.UMP.Parser.parse_frame/1`.
   - Explicitly rescue `MatchError` and `FunctionClauseError` to prevent process crashes without over-catching.
   - Verify file contents via `read_file`.

3. **Update Continuous AX Audit (`GovernanceCore.AXAudit`)**
   - Read and modify `governance_core/lib/governance_core/ax_audit.ex`.
   - Add specific monitoring for `/api/mcp` alongside existing endpoints.
   - Use `:timer.tc` for checking the response time of `/api/mcp`. If it exceeds 1000ms, use the static error `{:error, :timeout}`.
   - Use `Req.get(url, decode_body: false)` to fetch the endpoint without failing on decode errors.
   - If an error is detected, trigger an automated PR mechanism.
   - PR logic will wrap `System.cmd("gh", ...)` and `git` commands in `try/rescue ErlangError` and handle exit codes via `case`. Deduplicate using `gh pr list --search "in:title 🤖 [AX Audit] Automated Fix"`. Use `git add` and `git commit` to source files in `priv/` (not build paths).
   - Verify file via `read_file`.

4. **Implement SkillTracker GenServer (`GovernanceCore.Monitoring.SkillTracker`)**
   - Create `governance_core/lib/governance_core/monitoring/skill_tracker.ex`.
   - A GenServer running periodically. Discovers modules via `:application.get_key(:governance_core, :modules)`.
   - Converts documentation info to YAML format. Explicitly indents any multiline string values correctly for YAML block scalars (`key: |`).
   - Calculates the dynamic string length of the YAML payload while adding items, chunking into multiple files to enforce a strict 1024-character limit per file (e.g., `SKILL.md`, `SKILL_2.md`).
   - Writes generated files to the source directory using `Path.join(File.cwd!(), "priv")`.
   - Uses `File.write/2` with a `case` statement to handle I/O errors gracefully.
   - Verify via `list_files` and `read_file`.

5. **Implement ResourceWatchdog GenServer (`GovernanceCore.Monitoring.ResourceWatchdog`)**
   - Create `governance_core/lib/governance_core/monitoring/resource_watchdog.ex`.
   - A GenServer with a continuous 5-minute interval (`5 * 60 * 1000` ms).
   - Monitors CPU and RAM using `System.cmd("docker", ["stats", "--no-stream"])`.
   - Wrapped in `try/rescue e in ErlangError` and handles non-zero exit codes with `case` to prevent `MatchError` if `docker` is missing.
   - Parses stdout to find containers exceeding 80% resource usage, then logs warnings instead of modifying files.
   - Verify via `read_file`.

6. **Implement Nightly Security Audit (`GovernanceCore.Monitoring.NightlyAudit`)**
   - Create `governance_core/lib/governance_core/monitoring/nightly_audit.ex`.
   - A GenServer running nightly (every 24 hours: `24 * 60 * 60 * 1000` ms).
   - Retrieves the log file path dynamically from the application environment via `Application.get_env(:governance_core, :audit_log_path)`. If not set or file does not exist, do nothing or log a warning.
   - Checks file size against `last_byte_pos`. If smaller (truncated/rotated), resets to 0. Otherwise, seeks via `:file.position` and uses `IO.binstream` with `Enum.reduce/3` to lazily process logs.
   - Filters logs for CRITICAL, ERROR, DENIED.
   - Generates summary in 'Decompiler Standard' format with headers: `--- DECOMPILER STANDARD AUDIT ---`, `TIMESTAMP:`, `SOURCE: HUMAN_IN_THE_LOOP`, `TRAFFIC_SNIPPET:`, and `STATUS: ANALYZED`.
   - Verify file via `read_file`.

7. **Register GenServers in Application Tree**
   - Modify `governance_core/lib/governance_core/application.ex` to add `GovernanceCore.Protocols.Fuzzer`, `GovernanceCore.AXAudit`, `GovernanceCore.Monitoring.SkillTracker`, `GovernanceCore.Monitoring.ResourceWatchdog`, and `GovernanceCore.Monitoring.NightlyAudit` to the supervision tree.
   - Verify via `read_file`.

8. **Run tests**
   - Run all relevant tests (unit, integration, etc.) to ensure the changes are correct and have not introduced regressions.

9. **Pre-commit Checks**
   - Complete pre-commit steps to ensure proper testing, verification, review, and reflection are done.

10. **Submit Change**
    - Submit using a descriptive commit message.
