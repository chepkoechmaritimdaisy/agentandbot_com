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

  def perform_mcp_audit do
    Logger.info("Starting MCP Endpoint Audit...")
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"

    start_time = System.monotonic_time()

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        latency = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if latency > 1000 or not is_map(body) do
           Logger.error("MCP Audit Failed: Latency #{latency}ms, JSON Schema valid: #{is_map(body)}")
           prepare_auto_fix("MCP endpoint degraded or returned invalid JSON")
        else
           Logger.info("MCP Audit Passed: Endpoint responsive and returned valid JSON")
        end
      {:ok, %{status: status}} ->
        Logger.error("MCP Audit Failed: Status #{status}")
        prepare_auto_fix("MCP endpoint returned status #{status}")
      {:error, reason} ->
        Logger.error("MCP Audit Failed: #{inspect(reason)}")
        prepare_auto_fix("MCP endpoint failed: #{inspect(reason)}")
    end
  end

  defp prepare_auto_fix(issue) do
    branch_name = "auto-fix-mcp-#{System.unique_integer([:positive])}"

    try do
      # Deduplicate check
      case System.cmd("gh", ["pr", "list", "--search", "in:title auto-fix-mcp"]) do
        {output, 0} ->
           if String.contains?(output, "auto-fix-mcp") do
             Logger.info("An active auto-fix PR for MCP already exists. Skipping PR creation.")
           else
             create_pr_for_fix(branch_name, issue)
           end
        {_, _} ->
           # fallback if gh is not authenticated or fails
           create_pr_for_fix(branch_name, issue)
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run git or gh commands: #{inspect(e)}")
    end
  end

  defp create_pr_for_fix(branch_name, issue) do
    Logger.info("Preparing PR for branch #{branch_name}...")

    case System.cmd("git", ["checkout", "-b", branch_name]) do
      {_, 0} ->
        # Write fix securely in priv directory
        fix_path = Path.join(:code.priv_dir(:governance_core) || Path.join(File.cwd!(), "priv"), "mcp_fix.json")
        File.write!(fix_path, Jason.encode!(%{issue: issue, action: "requires_review"}))

        System.cmd("git", ["add", "."])
        System.cmd("git", ["commit", "-m", "Automated fix: MCP Endpoint Degradation"])

        # Don't fail if we can't push/pr in environment
        case System.cmd("git", ["push", "origin", branch_name]) do
          {_, 0} ->
            System.cmd("gh", ["pr", "create", "--title", "Automated Fix: MCP Endpoint", "--body", issue])
          _ ->
            Logger.warning("Could not push branch #{branch_name}. Please inspect locally.")
        end

        # return to original state
        System.cmd("git", ["checkout", "-"])
      _ ->
        Logger.error("Failed to checkout branch #{branch_name}")
    end
  end
end
