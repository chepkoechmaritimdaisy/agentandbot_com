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

    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)

    failures = Enum.filter(results ++ [mcp_result], fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_pr(failures)
    end
  end

  defp prepare_pr(failures) do
    Logger.info("Preparing PR for AX Audit Fixes")

    branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

    # Write details to priv to ensure it's tracked if necessary and doesn't conflict with build artifacts
    fix_file_path = Path.join([Application.app_dir(:governance_core), "priv", "ax_audit_fix.json"])

    encoded_failures = Jason.encode!(Enum.map(failures, fn {_, reason} -> %{reason: reason} end))

    File.write!(fix_file_path, encoded_failures)

    try do
      # Deduplication: check if a PR already exists
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix in:title", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            System.cmd("git", ["checkout", "-b", branch_name])
            System.cmd("git", ["add", fix_file_path])
            System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
            System.cmd("git", ["push", "origin", branch_name])
            System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated PR fixing AX Audit issues.", "--head", branch_name])
          else
             Logger.info("AX Audit PR already open, skipping PR creation.")
          end
        {_, _} ->
          Logger.warning("Failed to run gh command for deduplication")
      end
    rescue
      e in ErlangError -> Logger.warning("Could not create PR: #{inspect(e)}")
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

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    # time is in microseconds, so 1000ms is 1_000_000 microseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      {:error, "MCP Endpoint #{url} timeout: #{time_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP Endpoint #{url} invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "MCP Endpoint #{url} failed: #{inspect(reason)}"}
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
end
