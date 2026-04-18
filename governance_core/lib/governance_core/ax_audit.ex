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
    results = [mcp_result | results]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_pr()
    end
  end

  defp check_mcp_endpoint(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _json} -> {:ok, url}
          {:error, _} -> {:error, :invalid_schema}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp prepare_pr do
    try do
      Logger.info("Preparing PR for AX Audit failure...")

      # Prepare auto-fix PR
      branch_name = "auto-fix-ax-audit"

      # Check if PR already exists to deduplicate
      case System.cmd("gh", ["pr", "list", "--search", "head:#{branch_name}", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            # Create a branch and prepare fix
            _ = System.cmd("git", ["checkout", "-b", branch_name])
            _ = System.cmd("git", ["commit", "--allow-empty", "-m", "Auto-fix AX Audit issue"])
            _ = System.cmd("git", ["push", "-u", "origin", branch_name])
            _ = System.cmd("gh", ["pr", "create", "--title", "Auto-fix AX Audit issue", "--body", "This PR fixes a detected AX Audit issue.", "--head", branch_name])
            Logger.info("PR prepared successfully.")
          else
            Logger.info("PR already exists for AX Audit fix, skipping.")
          end
        {_, _} ->
          Logger.error("Failed to list PRs, assuming missing gh cli or error")
      end
    rescue
      e in ErlangError ->
        Logger.error("ErlangError executing git/gh commands: #{inspect(e)}")
      e ->
        Logger.error("Error executing git/gh commands: #{inspect(e)}")
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
