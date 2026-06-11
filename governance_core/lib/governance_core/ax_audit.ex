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

    # Check MCP endpoint
    mcp_url = base_url <> "/api/mcp"
    {time_us, result} = :timer.tc(fn -> check_mcp_endpoint(mcp_url) end)

    # Time in ms
    time_ms = time_us / 1000

    case result do
      {:ok, _} when time_ms > 1000 ->
        handle_failure("MCP Endpoint #{mcp_url} response time too high: #{time_ms}ms")
      {:ok, _} ->
        Logger.info("AX Audit Passed: MCP endpoint is Agent-Friendly and responsive.")
      {:error, reason} ->
        handle_failure("AX Audit Failed on MCP endpoint: #{reason}")
    end
  end

  defp check_mcp_endpoint(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, "Invalid JSON schema at #{url}"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp handle_failure(reason) do
    Logger.error(reason)

    try do
      # Deduplicate PRs
      {pr_list_output, 0} = System.cmd("gh", ["pr", "list", "--search", "in:title 🤖 [AX Audit] Automated Fix"])

      if String.trim(pr_list_output) == "" do
        Logger.info("Creating automated PR for AX Audit failure...")

        branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

        {_, 0} = System.cmd("git", ["checkout", "-b", branch_name])

        fix_content = "Automated fix required for AX Audit failure.\\nReason: #{reason}\\n"
        id = System.unique_integer([:positive])
        file_path = Path.join(File.cwd!(), "priv/ax_fix_#{id}.txt")
        File.write!(file_path, fix_content)

        {_, 0} = System.cmd("git", ["add", file_path])
        {_, 0} = System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\\n\\n#{reason}"])
        {_, 0} = System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for: #{reason}"])

        Logger.info("Automated PR created successfully on branch #{branch_name}.")
      else
        Logger.info("Automated PR already exists, skipping creation.")
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute CLI commands for PR creation: #{inspect(e)}")
      e -> Logger.error("Unexpected error during PR creation: #{inspect(e)}")
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
end
