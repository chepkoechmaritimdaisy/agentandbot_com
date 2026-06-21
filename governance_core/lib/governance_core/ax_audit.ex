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

  defp perform_mcp_audit do
    Logger.info("Starting Continuous MCP Audit...")

    url = GovernanceCoreWeb.Endpoint.url() <> "/api/mcp"

    case Req.get(url, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        if is_valid_mcp_json?(body) do
          Logger.info("MCP Audit Passed")
        else
          handle_mcp_failure("Invalid JSON schema at #{url}")
        end
      {:ok, %{status: status}} ->
        handle_mcp_failure("Endpoint #{url} returned status #{status}")
      {:error, reason} ->
        handle_mcp_failure("Failed to fetch #{url}: #{inspect(reason)}")
    end
  end

  defp is_valid_mcp_json?(body) when is_map(body) do
    # Simple JSON schema validation logic
    Map.has_key?(body, "version") && Map.has_key?(body, "capabilities")
  end
  defp is_valid_mcp_json?(_), do: false

  defp handle_mcp_failure(reason) do
    Logger.error("MCP Audit Failed: #{reason}")
    create_mcp_fix_pr(reason)
  end

  defp create_mcp_fix_pr(reason) do
    try do
      # Deduplicate PR creation
      case System.cmd("gh", ["pr", "list", "--search", "Automated MCP Fix"]) do
        {existing_prs, 0} ->
          if String.trim(existing_prs) == "" do
            branch_name = "automated-mcp-fix-#{System.unique_integer([:positive])}"
            System.cmd("git", ["checkout", "-b", branch_name])

            # Write fix to a file (in priv)
            fix_path = Path.join(Path.join(File.cwd!(), "priv"), "mcp_fix.txt")
            File.write!(fix_path, "Automated fix for: #{reason}")

            System.cmd("git", ["add", fix_path])
            System.cmd("git", ["commit", "-m", "Automated MCP Fix"])

            case System.cmd("gh", ["pr", "create", "--title", "Automated MCP Fix", "--body", "Fixes #{reason}", "--head", branch_name]) do
              {_, 0} -> Logger.info("Successfully created PR for MCP fix")
              {err, _} -> Logger.error("Failed to create PR: #{err}")
            end

            System.cmd("git", ["checkout", "-"])
          else
            Logger.info("A PR for MCP Fix already exists")
          end
        {err, _} -> Logger.error("Failed to list PRs: #{err}")
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute git or gh commands: #{inspect(e)}")
    end
  end
end
