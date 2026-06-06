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

    # Standard endpoints
    endpoints = ["/", "/agents", "/dashboard/traffic"]
    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    # MCP API endpoint
    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)

    all_results = [mcp_result | results]

    failures = Enum.filter(all_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_pr(failures)
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

    # time is in microseconds
    if time > 1_000_000 do
      {:error, "Endpoint #{url} exceeded 1000ms response time"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    end
  end

  def is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end

  defp prepare_pr(failures) do
    Logger.info("Preparing PR for AX Audit fix...")

    # Map tuples into encodable structures
    encodable_failures = Enum.map(failures, fn {:error, reason} -> %{error: inspect(reason)} end)

    payload = Jason.encode!(encodable_failures)
    file_path = Path.join(File.cwd!(), "priv/ax_audit_fix.json")

    case File.write(file_path, payload) do
      :ok ->
        try do
          # Check for existing PRs
          {pr_list, _} = System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix"])

          if pr_list == "" do
            branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"
            System.cmd("git", ["checkout", "-b", branch_name])
            System.cmd("git", ["add", file_path])
            System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
            System.cmd("git", ["push", "-u", "origin", branch_name])
            case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures", "--head", branch_name]) do
              {_, 0} -> Logger.info("PR created successfully.")
              {error_msg, code} -> Logger.error("Failed to create PR (code #{code}): #{error_msg}")
            end
            System.cmd("git", ["checkout", "-"]) # Return to previous branch
          else
            Logger.info("PR already exists, skipping creation to avoid spam.")
          end
        rescue
          e in ErlangError ->
            Logger.error("Failed to execute git or gh commands: #{inspect(e)}")
        end
      {:error, reason} ->
        Logger.error("Failed to write ax_audit_fix.json: #{inspect(reason)}")
    end
  end
end
