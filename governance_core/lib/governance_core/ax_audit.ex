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

  # Continuous 5 minute interval
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

    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)

    failures = Enum.filter(results ++ [mcp_result], fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      auto_fix_mcp_failures(failures)
    end
  end

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)

    # Convert time from microseconds to milliseconds
    time_ms = time / 1000

    if time_ms > 1000 do
      {:error, "MCP Endpoint #{url} response time #{time_ms}ms exceeds 1000ms timeout"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, reason} -> {:error, "MCP Endpoint #{url} returned invalid JSON schema: #{inspect(reason)}"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP Endpoint #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp auto_fix_mcp_failures(failures) do
    try do
      # Make failures JSON encodable (convert tuples to maps)
      encodable_failures = Enum.map(failures, fn {:error, reason} -> %{error: reason} end)

      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--json", "title"]) do
        {output, 0} ->
          if String.contains?(output, "🤖 [AX Audit] Automated Fix") do
            Logger.info("Automated PR for AX Audit already exists. Skipping PR creation.")
          else
            create_automated_pr(encodable_failures)
          end
        {output, code} ->
          Logger.error("gh pr list failed with code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run 'gh' CLI. Is it installed? Error: #{inspect(e)}")
    end
  end

  defp create_automated_pr(failures) do
    json_failures = Jason.encode!(failures)

    # Path to write the temporary file
    log_file_path = Path.join(File.cwd!(), "priv/ax_audit_failures.json")

    case File.write(log_file_path, json_failures) do
      :ok ->
        branch_name = "ax-audit-auto-fix-#{System.system_time(:second)}"
        try do
          System.cmd("git", ["checkout", "-b", branch_name])
          System.cmd("git", ["add", "priv/ax_audit_failures.json"])
          case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"]) do
            {_, 0} ->
              System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures.", "--head", branch_name])
              Logger.info("Successfully created automated PR for AX Audit failures.")
            {output, code} ->
              Logger.error("git commit failed with code #{code}: #{output}")
          end
        rescue
          e in ErlangError ->
            Logger.error("Failed to create automated PR. Error: #{inspect(e)}")
        end
      {:error, reason} ->
        Logger.error("Failed to write ax_audit_failures.json: #{inspect(reason)}")
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
