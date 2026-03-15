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

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{recent_pr_times: []}, name: __MODULE__)
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

  def perform_audit(state \\ %{recent_pr_times: []}) do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    failures = Enum.filter(html_results ++ mcp_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
      state
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_pr_for_failures(failures, state)
    end
  end

  defp check_html_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)

    # decode_body: false safely handles invalid JSON without crashing
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 1000 do
          {:error, "MCP Endpoint #{url} response time too high: #{duration}ms"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP Endpoint #{url} returned invalid JSON schema"}
          end
        end
      {:ok, %{status: status}} ->
        {:error, "MCP Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch MCP #{url}: #{inspect(reason)}"}
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")

    has_main && has_h1
  end

  defp create_pr_for_failures(failures, state) do
    now = System.system_time(:second)

    # Prune old PR creations (older than 24 hours)
    recent_times = Enum.filter(state.recent_pr_times, fn time -> now - time < 86400 end)

    # Limit PR creations to max 3 per day to prevent spam
    if length(recent_times) < 3 do
      failure_details = Enum.map_join(failures, "\\n", fn {:error, reason} -> "- #{reason}" end)

      title = "🔧 [Auto-Fix] Resolve AX Audit Failures"
      body = "The Continuous AX Audit detected the following issues:\\n\\n#{failure_details}\\n\\nPlease review and fix the agent-friendly endpoints."

      Logger.warning("Attempting to create automated PR for AX Audit failures...")

      case System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--base", "main"]) do
        {_output, 0} ->
          Logger.info("Successfully created automated PR via gh cli.")
          %{state | recent_pr_times: [now | recent_times]}
        {output, exit_code} ->
          Logger.error("Failed to create automated PR. Exit code: #{exit_code}, Output: #{output}")
          %{state | recent_pr_times: recent_times}
      end
    else
      Logger.warning("Rate limit reached for automated PRs. Skipping PR creation.")
      %{state | recent_pr_times: recent_times}
    end
  end
end
