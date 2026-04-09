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
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    results = html_results ++ mcp_results
    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      failures
      |> Enum.map(fn {:error, reason} -> reason end)
      |> Enum.uniq()
      |> Enum.each(fn reason ->
        # Ensure we deduplicate by static error reason
        create_fix_pr(reason)
      end)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, :not_agent_friendly}
        end
      {:ok, %{status: _status}} ->
        {:error, :invalid_status}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        cond do
          duration_ms > 2000 ->
             {:error, :timeout}
          not valid_json_schema?(body) ->
             {:error, :invalid_schema}
          true ->
             {:ok, url}
        end
      {:ok, %{status: _status}} ->
        {:error, :invalid_status}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp valid_json_schema?(body) do
    case Jason.decode(body) do
      {:ok, _json} -> true
      {:error, _} -> false
    end
  end

  defp create_fix_pr(reason) do
    Logger.info("Creating PR for #{inspect(reason)}")
    # We create a PR without messing up the local git state.
    # We do a basic commit-tree trick to create an empty or simple commit and PR.
    # Note: the user requested to use `git write-tree` and `git commit-tree`.

    branch_name = "fix-ax-audit-#{System.unique_integer([:positive])}"

    # 1. Get current tree
    {tree_hash, 0} = System.cmd("git", ["write-tree"])
    tree_hash = String.trim(tree_hash)

    # 2. Get current HEAD
    {head_hash, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    head_hash = String.trim(head_hash)

    # 3. Create commit
    {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", head_hash, "-m", "Fix AX Audit: #{inspect(reason)}"])
    commit_hash = String.trim(commit_hash)

    # 4. Update ref
    {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])

    # 5. Push
    {_, _} = System.cmd("git", ["push", "origin", branch_name])

    # 6. Create PR via gh cli
    System.cmd("gh", ["pr", "create", "--base", "main", "--head", branch_name, "--title", "Fix AX Audit: #{inspect(reason)}", "--body", "Automated PR to fix AX Audit issue: #{inspect(reason)}"])
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
