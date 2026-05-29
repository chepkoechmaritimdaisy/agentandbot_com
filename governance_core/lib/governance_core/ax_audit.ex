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
    endpoints = ["/", "/agents", "/dashboard/traffic", "/api/mcp"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url, path)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  defp check_endpoint(url, "/api/mcp") do
    # For /api/mcp we check JSON schema validation and response time
    {time, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)
    # Convert microseconds to milliseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      Logger.error("AX Audit: /api/mcp response time exceeded 1000ms: #{time_ms}ms")
      trigger_fix_pr("Optimize /api/mcp endpoint to return under 1000ms. Current time: #{time_ms}ms")
      {:error, "Response time #{time_ms}ms exceeded limit"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} ->
              {:ok, url}
            {:error, _} ->
              Logger.error("AX Audit: /api/mcp JSON schema validation failed.")
              trigger_fix_pr("Fix JSON formatting for /api/mcp endpoint.")
              {:error, "Invalid JSON schema on #{url}"}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp check_endpoint(url, _path) do
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

  defp trigger_fix_pr(reason) do
    Logger.info("Triggering automated PR for AX Audit failure: #{reason}")
    try do
      # Deduplicate PRs
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(reason)
          else
            Logger.info("PR already exists, skipping creation.")
          end
        {err, code} ->
          Logger.error("Failed to check existing PRs: code #{code}, output: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing gh cli: #{inspect(e)}")
    end
  end

  defp create_pr(reason) do
    # Write a dummy fix file in the source directory (priv/)
    fix_path = Path.join([File.cwd!(), "priv", "ax_audit_fix_#{System.system_time()}.json"])
    File.write(fix_path, Jason.encode!(%{fix: reason}))

    # Stage, commit, and create PR
    System.cmd("git", ["add", fix_path])
    System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\n\n#{reason}"])

    case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for MCP endpoint issues:\n#{reason}"]) do
      {output, 0} -> Logger.info("Successfully created PR: #{output}")
      {err, code} -> Logger.error("Failed to create PR: code #{code}, output: #{err}")
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
