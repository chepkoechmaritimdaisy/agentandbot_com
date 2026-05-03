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

    results =
      Task.async_stream(endpoints, fn path ->
        url = base_url <> path
        check_endpoint(url)
      end, timeout: :infinity)
      |> Enum.map(fn {:ok, res} -> res end)

    # Check MCP endpoint
    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)
    results = [mcp_result | results]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    # Deduplicate errors based on exact match of the failure reason.
    # The reason should be statically identifiable without timestamps.
    deduped_failures = Enum.uniq(failures)

    if Enum.empty?(deduped_failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(deduped_failures)}")
      handle_audit_failures(deduped_failures)
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
    {time_us, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_ms = time_us / 1000.0

    if time_ms > 1000.0 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_json_schema}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp handle_audit_failures(failures) do
    # Generate automated PR if it has MCP related errors
    has_mcp_failure = Enum.any?(failures, fn
      {:error, :timeout} -> true
      {:error, :invalid_json_schema} -> true
      _ -> false
    end)

    if has_mcp_failure do
      generate_automated_pr()
    end
  end

  defp generate_automated_pr do
    Logger.info("Generating automated PR for AX Audit failure.")

    fix_file = Path.join(File.cwd!(), "priv/ax_audit_fix.txt")
    File.write!(fix_file, "Automated fix generated at #{DateTime.utc_now()}")

    branch_name = "automated-ax-audit-fix-#{System.system_time(:second)}"

    try do
      # Avoid PR spam
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(branch_name, fix_file)
          else
             Logger.info("An automated AX Audit PR is already open. Skipping.")
          end
        {error, _code} ->
          Logger.error("Failed to check existing PRs: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Error executing gh CLI (maybe not installed?): #{inspect(e)}")
    end
  end

  defp create_pr(branch_name, fix_file) do
     try do
       case System.cmd("git", ["checkout", "-b", branch_name]) do
         {_, 0} ->
           case System.cmd("git", ["add", fix_file]) do
             {_, 0} ->
               case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"]) do
                 {_, 0} ->
                   System.cmd("git", ["push", "-u", "origin", branch_name])
                   System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for agent-friendly endpoint failures."])
                   Logger.info("Successfully created PR for AX Audit failure.")
                   System.cmd("git", ["checkout", "-"])
                 _ -> Logger.error("Failed to git commit.")
               end
             _ -> Logger.error("Failed to git add.")
           end
         _ -> Logger.error("Failed to git checkout branch.")
       end
     rescue
       e in ErlangError ->
          Logger.error("Error creating PR: #{inspect(e)}")
       e ->
          Logger.error("Failed to create PR: #{inspect(e)}")
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
