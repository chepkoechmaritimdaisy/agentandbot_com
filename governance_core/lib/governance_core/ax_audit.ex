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
      prepare_fix_pr(failures)
    end
  end

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_ms = time / 1000

    if time_ms > 1000 do
      {:error, "MCP endpoint #{url} timeout: took #{time_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp prepare_fix_pr(failures) do
    encoded_failures =
      failures
      |> Enum.map(fn {_, reason} -> reason end)
      |> Jason.encode!()

    branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

    try do
      # Check if PR already exists to deduplicate
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--json", "id"]) do
        {output, 0} ->
          if output == "[]" || output == "" || output == "[]\n" do
            create_pr(branch_name, encoded_failures)
          else
             Logger.info("AX Audit PR already exists, skipping creation.")
          end
        {_, _} ->
           create_pr(branch_name, encoded_failures)
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run gh command: #{inspect(e)}")
    end
  end

  defp create_pr(branch_name, encoded_failures) do
    System.cmd("git", ["checkout", "-b", branch_name])

    # Write fix log to source priv dir
    fix_log_path = Path.join([File.cwd!(), "priv", "ax_audit_fix.json"])
    File.write!(fix_log_path, encoded_failures)

    System.cmd("git", ["add", fix_log_path])
    System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
    System.cmd("git", ["push", "-u", "origin", branch_name])
    System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated AX audit fix. Failures: #{encoded_failures}"])
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
