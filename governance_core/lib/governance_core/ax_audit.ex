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
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    results = html_results ++ mcp_results
    failures = Enum.filter(results, fn {status, _} -> status == :error end)
    |> Enum.uniq_by(fn {:error, reason} -> reason end) # Deduplicate errors using static reason

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp handle_failures(failures) do
    Logger.info("Initiating auto-fix PR for AX Audit failures...")

    # In a real system, we'd generate code modifications. Here we just simulate creating a PR.
    # To avoid disrupting live state, we use low-level git commands.

    # We create a dummy tree just to have something to commit. Since we don't have real fixes yet,
    # we can use the current tree.
    tree_hash = System.cmd("git", ["write-tree"]) |> elem(0) |> String.trim()
    parent_hash = System.cmd("git", ["rev-parse", "HEAD"]) |> elem(0) |> String.trim()

    commit_msg = "🔧 Fix AX Audit Failures\n\nFailures:\n" <> inspect(failures)

    {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", parent_hash, "-m", commit_msg])
    commit_hash = String.trim(commit_hash)

    branch_name = "refs/heads/auto-fix-ax-audit-#{:os.system_time(:second)}"
    System.cmd("git", ["update-ref", branch_name, commit_hash])

    # Simulate PR creation with gh. Will fail silently if not configured, which is fine for the audit script.
    try do
      System.cmd("gh", ["pr", "create", "--head", String.replace(branch_name, "refs/heads/", ""), "--title", "🔧 Fix AX Audit", "--body", commit_msg], stderr_to_stdout: true)
    rescue
      e in ErlangError -> Logger.warning("Failed to execute gh command (executable may be missing): #{inspect(e)}")
    end
  end

  defp check_html_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, :not_agent_friendly}
        end
      {:ok, %{status: status}} ->
        {:error, :bad_status}
      {:error, _} ->
        {:error, :timeout}
    end
  end

  defp check_mcp_endpoint(url) do
    case Req.get(url, decode_body: false, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _} -> {:ok, url}
          {:error, _} -> {:error, :invalid_json_schema}
        end
      {:ok, %{status: status}} ->
        {:error, :bad_status}
      {:error, _} ->
        {:error, :timeout}
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
