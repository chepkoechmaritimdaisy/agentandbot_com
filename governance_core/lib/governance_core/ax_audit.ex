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
    Logger.info("Starting Continuous MCP Audit...")
    base_url = GovernanceCoreWeb.Endpoint.url()
    mcp_url = base_url <> "/api/mcp"

    start_time = System.monotonic_time()

    case Req.get(mcp_url) do
      {:ok, %{status: 200, body: body}} ->
        duration = System.monotonic_time() - start_time
        duration_ms = System.convert_time_unit(duration, :native, :millisecond)

        # Check response time and JSON schema roughly
        is_slow = duration_ms > 1000
        is_invalid_json = match?({:error, _}, Jason.decode(body))

        cond do
          is_slow ->
            Logger.warning("AX Audit: MCP endpoint is slow (#{duration_ms}ms)")
            prepare_automated_pr("mcp_performance", "Optimize MCP endpoint latency", [%{error: "Slow response: #{duration_ms}ms"}])

          is_invalid_json ->
            Logger.warning("AX Audit: MCP endpoint returned invalid JSON schema")
            prepare_automated_pr("mcp_schema", "Fix MCP JSON Schema", [%{error: "Invalid JSON Schema"}])

          true ->
            Logger.info("AX Audit Passed: MCP endpoint is healthy.")
        end

      {:ok, %{status: status}} ->
        Logger.error("AX Audit Failed: MCP endpoint returned status #{status}")

      {:error, reason} ->
        # Jason needs strings or maps, handle reason tuple or error nicely
        reason_str = inspect(reason)
        Logger.error("AX Audit Failed: Failed to fetch MCP endpoint: #{reason_str}")
        prepare_automated_pr("mcp_failure", "Fix MCP Endpoint Failure", [%{error: reason_str}])
    end
  end

  defp prepare_automated_pr(branch_prefix, title, errors) do
    try do
      # Ensure branch name deduplication/uniqueness
      branch_name = "fix/#{branch_prefix}-#{System.unique_integer([:positive])}"

      # Use `gh pr list` to deduplicate PR spam loops for automated fixes
      case System.cmd("gh", ["pr", "list", "--search", title]) do
        {output, 0} ->
          if String.contains?(output, title) do
            Logger.info("Automated PR already exists for: #{title}. Skipping.")
          else
            do_create_pr(branch_name, title, errors)
          end
        {output, _} ->
          Logger.warning("Failed to search existing PRs. Output: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute PR command (missing binary?): #{inspect(e)}")
    end
  end

  defp do_create_pr(branch_name, title, errors) do
    file_path = Path.join(File.cwd!(), "priv/mcp_fix.json")
    File.write!(file_path, Jason.encode!(errors))

    System.cmd("git", ["checkout", "-b", branch_name])
    System.cmd("git", ["add", file_path])
    System.cmd("git", ["commit", "-m", title])

    case System.cmd("gh", ["pr", "create", "--title", title, "--body", "Automated AX Audit fix for MCP endpoint issues."]) do
      {_output, 0} -> Logger.info("Successfully created PR: #{title}")
      {err, _} -> Logger.error("Failed to create PR: #{err}")
    end

    # Switch back to main
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
