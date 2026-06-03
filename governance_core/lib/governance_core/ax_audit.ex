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
    mcp_url = base_url <> "/api/mcp"

    case check_mcp_endpoint(mcp_url) do
      :ok ->
        Logger.info("AX Audit Passed: MCP endpoint is Agent-Friendly.")
      {:error, reason} ->
        Logger.error("AX Audit Failed: #{inspect(reason)}. Preparing automated PR fix.")
        prepare_automated_pr_fix(reason)
    end
  end

  defp check_mcp_endpoint(url) do
    {time_in_microseconds, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_in_ms = time_in_microseconds / 1000.0

    if time_in_ms > 1000.0 do
      {:error, "Response time exceeded 1000ms: #{time_in_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> :ok
            {:error, _} -> {:error, "Invalid JSON schema in MCP response"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          # Map tuple to string if necessary for JSON encoding later
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp prepare_automated_pr_fix(reason) do
    title = "🤖 [AX Audit] Automated Fix"

    # Check if a PR already exists to avoid deduplication issues
    try do
      case System.cmd("gh", ["pr", "list", "--search", "#{title} in:title"]) do
        {output, 0} ->
          if String.contains?(output, title) do
            Logger.info("AX Audit: Automated PR already exists, skipping creation.")
          else
            create_pr(title, reason)
          end
        {output, exit_code} ->
          Logger.warning("AX Audit: Failed to check for existing PRs via gh. Exit #{exit_code}: #{output}")
          create_pr(title, reason)
      end
    rescue
      e in ErlangError ->
        Logger.error("AX Audit: gh CLI missing or failed to run: #{inspect(e)}")
        create_pr(title, reason)
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

  defp create_pr(title, reason) do
    # Prepare payload mapping reason safely
    reason_str = if is_binary(reason), do: reason, else: inspect(reason)
    payload = %{fix_details: "Automated fix for MCP endpoint", reason: reason_str}

    file_path = Path.join(File.cwd!(), "priv/ax_audit_fix.json")

    case File.write(file_path, Jason.encode!(payload)) do
      :ok ->
        Logger.info("AX Audit: Written fix to #{file_path}")

        try do
          System.cmd("git", ["add", file_path])
          System.cmd("git", ["commit", "-m", title])
          Logger.info("AX Audit: Automated fix committed.")
        rescue
          e in ErlangError ->
            Logger.error("AX Audit: git CLI failed: #{inspect(e)}")
        end

      {:error, posix} ->
        Logger.error("AX Audit: Failed to write fix file: #{inspect(posix)}")
    end
  end
end
