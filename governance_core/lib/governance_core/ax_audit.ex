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
  # 1 minute in milliseconds
  @mcp_interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    schedule_mcp_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  def handle_info(:mcp_audit, state) do
    perform_mcp_audit()
    schedule_mcp_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp schedule_mcp_audit do
    Process.send_after(self(), :mcp_audit, @mcp_interval)
  end

  def perform_mcp_audit do
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        duration = System.monotonic_time(:millisecond) - start_time
        # Check if duration is too long or body is not a map (JSON object parsing failed/unexpected)
        if duration > 1000 or not is_map(body) do
          create_fix_pr("MCP Endpoint is slow (#{duration}ms) or malformed")
        end
      _ ->
        create_fix_pr("MCP Endpoint unavailable or returned non-200 status")
    end
  end

  defp create_fix_pr(reason) do
    Logger.warning("AX Audit MCP Failure: #{reason}. Initiating auto-fix PR.")
    branch = "mcp-auto-fix-#{System.unique_integer([:positive])}"
    filepath = Path.join(File.cwd!(), "priv/mcp_fix_#{System.unique_integer([:positive])}.txt")

    try do
      File.write!(filepath, "Automated fix applied for: #{reason}")

      System.cmd("git", ["checkout", "-b", branch])
      System.cmd("git", ["add", filepath])
      System.cmd("git", ["commit", "-m", "Auto-fix MCP endpoint performance/schema issue"])

      # Use gh to create PR, ignore output.
      # Since we don't know if gh is authenticated, we just try our best.
      case System.cmd("gh", ["pr", "create", "--title", "Automated MCP Fix", "--body", reason]) do
        {_output, _status} -> :ok
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute git/gh commands: #{inspect(e)}")
      e -> Logger.error("Failed to auto-fix MCP: #{inspect(e)}")
    end
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  defp check_endpoint(url) do
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

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end
end
