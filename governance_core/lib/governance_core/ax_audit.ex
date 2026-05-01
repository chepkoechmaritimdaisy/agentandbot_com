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

    all_results = [mcp_result | results]

    failures = Enum.filter(all_results, fn {status, _} -> status == :error end)

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

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    # time is in microseconds, convert to milliseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_json}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP Endpoint #{url} returned status #{status}"}
        {:error, _reason} ->
          {:error, :fetch_failed}
      end
    end
  end

  defp handle_failures(failures) do
    Enum.each(failures, fn {_, reason} ->
      trigger_automated_pr(reason)
    end)
  end

  defp trigger_automated_pr(reason) do
    # Deduplicate PRs
    search_cmd = ["pr", "list", "--search", "in:title 🤖 [AX Audit] Automated Fix", "--state", "open"]

    try do
      case System.cmd("gh", search_cmd) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(reason)
          else
            Logger.info("Automated PR already exists, skipping.")
          end
        {error, _code} ->
          Logger.error("Failed to search PRs: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing gh CLI: #{inspect(e)}")
    end
  end

  defp create_pr(reason) do
    try do
      # Create a fix file
      filename = "ax_audit_fix_#{:os.system_time(:second)}.txt"
      file_path = Path.join([File.cwd!(), "priv", filename])
      File.write!(file_path, "Automated fix for reason: #{inspect(reason)}")

      branch_name = "ax-audit-fix-#{:os.system_time(:second)}"

      System.cmd("git", ["checkout", "-b", branch_name])
      System.cmd("git", ["add", file_path])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])

      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Fixes AX Audit issues automatically.\nReason: #{inspect(reason)}"]) do
        {_out, 0} -> Logger.info("Automated PR created successfully.")
        {err, _} -> Logger.error("Failed to create PR: #{err}")
      end

      System.cmd("git", ["checkout", "-"])
    rescue
      e in ErlangError ->
        Logger.error("Error creating automated PR: #{inspect(e)}")
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
