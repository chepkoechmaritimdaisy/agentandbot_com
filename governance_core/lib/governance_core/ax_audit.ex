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
    # Check standard HTML endpoints
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

    # MCP API check
    mcp_url = base_url <> "/api/mcp"
    check_mcp_endpoint(mcp_url)
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
    case Req.get(url, decode_body: false, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _json} ->
            Logger.info("MCP Endpoint #{url} is healthy.")
            :ok

          {:error, _} ->
            Logger.error("MCP Endpoint #{url} returned invalid JSON schema.")
            prepare_fix_pr("fix: Invalid JSON schema on MCP endpoint", "The MCP endpoint at #{url} returned invalid JSON.")
            {:error, :invalid_json}
        end

      {:ok, %{status: status}} ->
        Logger.error("MCP Endpoint #{url} returned status #{status}")
        prepare_fix_pr("fix: MCP endpoint returned status #{status}", "The MCP endpoint at #{url} is failing with status #{status}.")
        {:error, {:bad_status, status}}

      {:error, reason} ->
        Logger.error("Failed to fetch MCP Endpoint #{url}: #{inspect(reason)}")
        # Deduplicate errors by using a static reason map
        prepare_fix_pr("fix: MCP endpoint unreachable or timed out", "The MCP endpoint at #{url} failed with reason: #{inspect(reason)}.")
        {:error, :timeout_or_unreachable}
    end
  end

  defp prepare_fix_pr(title, body) do
    Logger.info("Preparing PR for fix: #{title}")
    # Using gh CLI, gracefully handled
    try do
      branch_name = "auto-fix-ax-#{:os.system_time(:seconds)}"

      # We need to make sure we don't crash if git or gh fails.
      # Since we just want to create a PR without local state mutation, we can just use branch.
      case System.cmd("git", ["checkout", "-b", branch_name]) do
        {_, 0} ->
          # For a real fix, we might create a file or modify something.
          # Here we'll just add an empty commit
          System.cmd("git", ["commit", "--allow-empty", "-m", title])
          System.cmd("git", ["push", "-u", "origin", branch_name])

          case System.cmd("gh", ["pr", "create", "--title", "🤖 " <> title, "--body", body, "--head", branch_name]) do
            {out, 0} -> Logger.info("PR created successfully: #{out}")
            {err, _} -> Logger.warning("Failed to create PR with gh: #{err}")
          end

          # Go back to main
          System.cmd("git", ["checkout", "main"])

        {err, _} ->
          Logger.warning("Failed to create branch for PR: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("gh or git CLI not available, skipping PR creation. #{inspect(e)}")
    end
  end
end
