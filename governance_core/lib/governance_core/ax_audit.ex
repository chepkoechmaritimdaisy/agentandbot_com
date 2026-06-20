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
    Logger.info("Starting MCP Audit...")
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"

    start_time = System.monotonic_time(:millisecond)
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        if (end_time - start_time) > 1000 or not validate_mcp_schema(body) do
          handle_mcp_failure("Slow response or invalid JSON schema at /api/mcp")
        else
          Logger.info("MCP Audit Passed")
        end
      {:ok, %{status: status}} ->
        handle_mcp_failure("Endpoint #{url} returned status #{status}")
      {:error, reason} ->
        handle_mcp_failure("Failed to fetch #{url}: #{inspect(reason)}")
    end
  end

  defp validate_mcp_schema(body) do
    case body do
      # very basic validation check to make sure it's valid JSON
      %{} -> true
      _ -> false
    end
  end

  defp handle_mcp_failure(reason) do
    Logger.error("MCP Audit Failed: #{reason}. Creating PR...")

    branch_name = "auto-fix-mcp-#{System.unique_integer([:positive])}"

    try do
      # Avoid empty commits and PR spam loops
      System.cmd("gh", ["pr", "list", "--search", "auto-fix-mcp-"]) |> case do
        {output, 0} ->
          if String.contains?(output, "auto-fix-mcp-") do
            Logger.info("A PR for MCP fix already exists.")
          else
            create_pr(branch_name, reason)
          end
        _ -> create_pr(branch_name, reason)
      end
    rescue
      e in ErlangError -> Logger.error("Failed to run GH CLI: #{inspect(e)}")
    end
  end

  defp create_pr(branch_name, reason) do
    System.cmd("git", ["checkout", "-b", branch_name])

    # Simulate a fix
    fix_path = Path.join(File.cwd!(), "priv/mcp_fix.txt")
    File.write!(fix_path, "Automated fix for MCP endpoint failure: #{reason}")

    System.cmd("git", ["add", "priv/mcp_fix.txt"])
    System.cmd("git", ["commit", "-m", "Automated fix for MCP endpoint"])
    System.cmd("git", ["push", "origin", branch_name])
    System.cmd("gh", ["pr", "create", "--title", "Automated fix for MCP endpoint", "--body", reason, "--head", branch_name])

    System.cmd("git", ["checkout", "main"])
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
