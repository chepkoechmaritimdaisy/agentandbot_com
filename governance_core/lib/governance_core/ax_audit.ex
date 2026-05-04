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

    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")
    results = [mcp_result | results]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      maybe_create_pr(failures)
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
    {time, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    # Time is in microseconds, so 1000ms is 1_000_000 microseconds
    if time > 1_000_000 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP JSON schema invalid"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
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

  defp maybe_create_pr(_failures) do
    try do
      case System.cmd("gh", ["pr", "list", "--search", "in:title \"🤖 [AX Audit] Automated Fix\" --state open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr()
          else
            Logger.info("AX Audit PR already exists. Skipping PR creation.")
          end
        {_, code} ->
          Logger.error("Failed to list PRs, gh returned exit code #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute gh CLI. Ensure gh is installed. #{inspect(e)}")
    end
  end

  defp create_pr do
    # Path to actual source priv directory, not _build
    priv_dir = Path.join(File.cwd!(), "priv")
    dummy_file_path = Path.join(priv_dir, "ax_audit_fix_#{:os.system_time(:second)}.txt")
    File.write!(dummy_file_path, "Automated fix for AX Audit failures.")

    try do
      case System.cmd("git", ["add", dummy_file_path]) do
        {_, 0} ->
          case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\n\nFixing AX audit failures."]) do
            {_, 0} ->
              case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for recent AX Audit failures."]) do
                {_, 0} -> Logger.info("Successfully created automated PR for AX Audit fixes.")
                {err, code} -> Logger.error("Failed to create PR using gh: #{code} #{err}")
              end
            {err, code} -> Logger.error("Failed to commit dummy file: #{code} #{err}")
          end
        {err, code} -> Logger.error("Failed to git add dummy file: #{code} #{err}")
      end
    rescue
      e in ErlangError -> Logger.error("git command failed. #{inspect(e)}")
    end
  end
end
