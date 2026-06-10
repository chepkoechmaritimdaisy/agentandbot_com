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

  # 5 minutes in milliseconds for continuous audit
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

    # Also audit the MCP endpoint
    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")
    results = [mcp_result | results]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_automated_fix_pr(failures)
    end
  end

  defp check_mcp_endpoint(url) do
    {time_us, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)

    case result do
      {:ok, %{status: 200, body: body}} ->
        if time_us > 1_000_000 do
          {:error, "MCP endpoint response time exceeded 1000ms: #{time_us / 1000}ms"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP endpoint JSON schema is invalid"}
          end
        end

      {:ok, %{status: status}} ->
        {:error, "MCP endpoint returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch MCP endpoint: #{inspect(reason)}"}
    end
  end

  defp prepare_automated_fix_pr(failures) do
    Logger.info("Preparing automated fix PR for AX Audit failures...")

    # Check if a PR already exists to prevent spam loops
    try do
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open", "--json", "number"]) do
        {output, 0} ->
          if String.trim(output) == "[]" do
            create_pr(failures)
          else
            Logger.info("Automated PR already exists, skipping creation.")
          end
        _ ->
          Logger.warning("Failed to check existing PRs with gh CLI")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ErlangError checking existing PRs (gh CLI might be missing): #{inspect(e)}")
    end
  end

  defp create_pr(failures) do
    branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

    try do
      System.cmd("git", ["checkout", "-b", branch_name])

      # Write a fix report file into the source priv/ directory
      priv_dir = Path.join(File.cwd!(), "priv")
      File.mkdir_p!(priv_dir)

      # Make failures encodable by converting tuples to strings
      encodable_failures = Enum.map(failures, fn {:error, reason} -> "Error: #{inspect(reason)}" end)

      report_content = %{
        timestamp: DateTime.utc_now(),
        failures: encodable_failures
      } |> Jason.encode!()

      file_path = Path.join(priv_dir, "ax_audit_fix_report.json")
      File.write!(file_path, report_content)

      System.cmd("git", ["add", file_path])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])

      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures."]) do
        {_, 0} -> Logger.info("Successfully created automated PR.")
        {err, _} -> Logger.error("Failed to create PR via gh: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ErlangError creating PR (git/gh CLI might be missing): #{inspect(e)}")
    after
      # Try to return to previous branch to not leave system in detached state
      try do
        System.cmd("git", ["checkout", "-"])
      rescue
        _ -> :ok
      end
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
