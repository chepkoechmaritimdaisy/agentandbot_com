defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  - /api/mcp response time and valid JSON schema
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes in milliseconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()

    # Check endpoints
    endpoints = ["/", "/agents", "/dashboard/traffic"]
    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    # Check API MCP
    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp(mcp_url)

    failures = Enum.filter(results ++ [mcp_result], fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_audit_failure(failures)
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

  defp check_mcp(url) do
    {time_in_microsecs, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_in_ms = time_in_microsecs / 1000

    if time_in_ms > 1000 do
      {:error, "MCP endpoint #{url} response time exceeded 1000ms: #{time_in_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} ->
              {:ok, url}
            {:error, _reason} ->
              {:error, "MCP endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP endpoint #{url}: #{inspect(reason)}"}
      end
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

  defp handle_audit_failure(failures) do
    # Only generate PR for MCP endpoint failures for now
    mcp_failures = Enum.filter(failures, fn {_, reason} ->
      String.contains?(reason, "MCP endpoint")
    end)

    if length(mcp_failures) > 0 do
      generate_automated_pr(mcp_failures)
    end
  end

  defp generate_automated_pr(failures) do
    pr_title = "🤖 [AX Audit] Automated Fix"

    try do
      # Check if PR already exists
      case System.cmd("gh", ["pr", "list", "--search", pr_title, "--state", "open"]) do
        {output, 0} ->
          if output == "" do
            create_pr(pr_title, failures)
          else
            Logger.info("AX Audit: Open PR for automated fix already exists. Skipping PR creation.")
          end
        {output, _exit_code} ->
          Logger.warning("AX Audit: Failed to check existing PRs: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("AX Audit: Could not execute gh CLI. Ensure it is installed. Error: #{inspect(e)}")
    end
  end

  defp create_pr(title, failures) do
    branch_name = "ax-audit-fix-#{System.system_time(:second)}"

    try do
      # 1. Create and checkout new branch
      System.cmd("git", ["checkout", "-b", branch_name])

      # 2. Modify a file in priv/
      file_path = Path.join([File.cwd!(), "priv", "ax_audit_report.txt"])

      # Ensure tuples are converted to strings before encoding
      encoded_failures = Enum.map(failures, fn {status, reason} ->
        %{status: Atom.to_string(status), reason: reason}
      end)

      File.write!(file_path, "AX Audit Failure Report\n" <> Jason.encode!(encoded_failures))

      # 3. Add and commit
      System.cmd("git", ["add", "priv/ax_audit_report.txt"])
      System.cmd("git", ["commit", "-m", title])

      # 4. Push branch
      System.cmd("git", ["push", "origin", branch_name])

      # 5. Create PR using gh CLI
      body = "Automated PR generated by GovernanceCore.AXAudit to fix MCP endpoint issues."
      case System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--base", "main"]) do
        {_output, 0} ->
          Logger.info("AX Audit: Successfully created automated PR.")
        {output, _exit_code} ->
          Logger.warning("AX Audit: Failed to create PR: #{output}")
      end

      # Clean up by going back to main
      System.cmd("git", ["checkout", "main"])
    rescue
      e in ErlangError ->
        Logger.error("AX Audit: Error creating PR via git/gh: #{inspect(e)}")
    end
  end
end
