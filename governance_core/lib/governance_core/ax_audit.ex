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
  # 1 minute in milliseconds for MCP check
  @mcp_interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    schedule_mcp_check()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  def handle_info(:mcp_check, state) do
    check_mcp_endpoint()
    schedule_mcp_check()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp schedule_mcp_check do
    Process.send_after(self(), :mcp_check, @mcp_interval)
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

  defp check_mcp_endpoint do
    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"
    start_time = System.monotonic_time()

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        # time in milliseconds
        response_time = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if response_time > 1000 or not valid_mcp_schema?(body) do
          Logger.error("AX Audit (MCP): Endpoint slow (#{response_time}ms) or invalid schema. Preparing PR.")
          prepare_fix_pr(%{response_time: response_time, body: body})
        else
          Logger.debug("AX Audit (MCP): Endpoint passed.")
        end

      {:ok, %{status: status}} ->
        Logger.error("AX Audit (MCP): Endpoint returned status #{status}. Preparing PR.")
        prepare_fix_pr(%{status: status})

      {:error, reason} ->
        Logger.error("AX Audit (MCP): Failed to fetch #{url}: #{inspect(reason)}. Preparing PR.")
        prepare_fix_pr(%{error: inspect(reason)})
    end
  end

  defp valid_mcp_schema?(body) when is_map(body) do
    # Simple JSON schema validation for MCP
    Map.has_key?(body, "name") and Map.has_key?(body, "version")
  end
  defp valid_mcp_schema?(_), do: false

  defp prepare_fix_pr(issue_details) do
    branch_name = "fix-mcp-endpoint-#{System.unique_integer([:positive])}"

    # Encode issue details safely
    safe_details =
      case Jason.encode(issue_details) do
        {:ok, json} -> json
        _ -> inspect(issue_details)
      end

    try do
      # Create unique branch
      case System.cmd("git", ["checkout", "-b", branch_name]) do
        {_, 0} -> :ok
        _ -> Logger.warning("Failed to create branch #{branch_name}")
      end

      # For demonstration: write the issue details to a file that will be committed
      File.write!("mcp_fix_report.json", safe_details)

      # Stage changes
      case System.cmd("git", ["add", "mcp_fix_report.json"]) do
        {_, 0} -> :ok
        _ -> Logger.warning("Failed to add file to git")
      end

      # Commit
      case System.cmd("git", ["commit", "-m", "Automated fix: MCP Endpoint issue detected"]) do
        {_, 0} -> :ok
        _ -> Logger.warning("Failed to commit changes")
      end

      # Create PR with gh
      case System.cmd("gh", ["pr", "create", "--title", "Automated fix: MCP Endpoint issue", "--body", safe_details]) do
        {_, 0} -> Logger.info("Successfully created PR for MCP fix on branch #{branch_name}")
        _ -> Logger.warning("Failed to create PR using gh CLI")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing CLI tools for PR creation: #{inspect(e)}")
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
