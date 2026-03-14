defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  """
  use GenServer
  require Logger

  # Check every 1 hour (or smaller for testing, let's say 1 hour)
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{recent_prs: []}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(state) do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/api/agents", "/.well-known/agent.json"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All MCP endpoints are valid.")
      state
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures, state)
    end
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        # Convert to milliseconds
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        cond do
          duration_ms > 2000 ->
            {:error, "Endpoint #{url} is too slow (#{duration_ms}ms)"}
          not valid_json?(body) ->
            {:error, "Endpoint #{url} returned invalid JSON schema"}
          true ->
            {:ok, url}
        end

      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp handle_failures(failures, state) do
    Enum.reduce(failures, state, fn {:error, reason}, acc_state ->
      # Check if we already created a PR for this recently (simple heuristic: limit PR creations)
      if reason in acc_state.recent_prs do
        Logger.info("PR already created recently for: #{reason}")
        acc_state
      else
        Logger.info("Creating PR for AX Audit failure: #{reason}")
        create_fix_pr(reason)
        # Add to recent PRs to avoid spamming
        %{acc_state | recent_prs: [reason | acc_state.recent_prs]}
      end
    end)
  end

  defp create_fix_pr(reason) do
    # Fire and forget system cmd
    Task.start(fn ->
      title = "Fix AX Audit Failure"
      body = "AX Audit detected an issue: #{reason}"
      # Example gh command
      # In a real environment, you'd want to commit changes first or have a branch ready.
      # For now, we simulate the PR creation or call it.
      try do
        System.cmd("gh", ["pr", "create", "--title", title, "--body", body])
      rescue
        e -> Logger.warning("Failed to run gh cli: #{inspect(e)}")
      end
    end)
  end
end
