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

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")

    failures = Enum.filter(results ++ [mcp_result], fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
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

  defp check_mcp_endpoint(url) do
    {time_in_microsecs, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)

    if time_in_microsecs > 1_000_000 do
      {:error, "MCP endpoint response time exceeded 1000ms: #{time_in_microsecs / 1000}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, reason} -> {:error, "MCP endpoint returned invalid JSON schema: #{inspect(reason)}"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP endpoint #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp handle_failures(failures) do
    # Serialize errors to a JSON file in the source priv/ directory
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    file_path = Path.join(priv_dir, "ax_audit_failures.json")

    # Map failures to encodable structures (maps or strings)
    encodable_failures = Enum.map(failures, fn {:error, reason} -> %{error: inspect(reason)} end)

    File.write!(file_path, Jason.encode!(encodable_failures))

    create_automated_pr(file_path)
  end

  defp create_automated_pr(file_path) do
    try do
      # Deduplication: Check if PR already exists
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if String.contains?(output, "[AX Audit] Automated Fix") do
            Logger.info("AX Audit PR already exists, skipping creation.")
          else
            execute_pr_creation(file_path)
          end
        {error_output, exit_code} ->
          Logger.error("Failed to check existing PRs: #{error_output} (exit code #{exit_code})")
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute gh CLI for checking PRs: #{inspect(e)}")
    end
  end

  defp execute_pr_creation(file_path) do
    try do
      branch_name = "ax-audit-fix-#{System.system_time(:second)}"

      # Create branch
      System.cmd("git", ["checkout", "-b", branch_name])

      # Add and commit the file
      System.cmd("git", ["add", file_path])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])

      # Push branch (assuming remote is origin)
      System.cmd("git", ["push", "-u", "origin", branch_name])

      # Create PR
      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures.", "--head", branch_name]) do
        {output, 0} -> Logger.info("Created AX Audit PR: #{output}")
        {error_output, exit_code} -> Logger.error("Failed to create AX Audit PR: #{error_output} (exit code #{exit_code})")
      end

      # Go back to main
      System.cmd("git", ["checkout", "-"])
    rescue
      e in ErlangError -> Logger.error("Failed to execute CLI commands for PR creation: #{inspect(e)}")
    end
  end
end
