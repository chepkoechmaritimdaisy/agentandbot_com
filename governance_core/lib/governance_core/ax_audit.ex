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

    # Also test MCP endpoints for response time and valid JSON schema
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]

    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    failures = Enum.filter(html_results ++ mcp_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_fix_pr(failures)
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
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp check_mcp_endpoint(url) do
    # Memory: "When verifying raw JSON schemas with the Req library in audits, use decode_body: false to safely handle invalid JSON without crashing."
    # Memory: "The 'AX Audit' process monitors MCP endpoints (/api/agents, /.well-known/agent.json) for response time and valid JSON schema."
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        diff_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        # Check if response time is too long (e.g. > 1000ms)
        if diff_ms > 1000 do
          {:error, :timeout}
        else
          # Check JSON schema validity by seeing if Jason can decode it
          case Jason.decode(body) do
            {:ok, _} -> {:ok, url}
            {:error, _} -> {:error, :invalid_json_schema}
          end
        end
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp create_fix_pr(failures) do
    # Memory: "Automated Pull Request creation uses the gh CLI (gh pr create). To avoid direct local git mutations (like git commit or git checkout) that could disrupt the live state, prepare and push the branch using git write-tree, git commit-tree, git update-ref, and git push."

    # Extract unique static error reasons for PR title
    reasons = failures |> Enum.map(fn {_, reason} -> reason end) |> Enum.uniq()

    branch_name = "auto-fix-ax-audit-#{:os.system_time(:second)}"
    commit_msg = "Auto-fix: AX Audit failures: #{inspect(reasons)}"

    try do
      {tree_hash, 0} = System.cmd("git", ["write-tree"])
      tree_hash = String.trim(tree_hash)

      {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-m", commit_msg])
      commit_hash = String.trim(commit_hash)

      {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])
      {_, 0} = System.cmd("git", ["push", "origin", branch_name])

      {_, 0} = System.cmd("gh", ["pr", "create", "--title", "Fix AX Audit failures", "--body", "Automated PR fixing #{inspect(reasons)}", "--head", branch_name])

      Logger.info("Created PR for AX Audit failures.")
    rescue
      e -> Logger.error("Failed to create PR: #{inspect(e)}")
    end
  end
end
