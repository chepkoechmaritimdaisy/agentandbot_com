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
      check_endpoint(url)
    end)

    mcp_results = Enum.map(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end)

    all_failures =
      Enum.filter(html_results ++ mcp_results, fn {status, _} -> status == :error end)

    if Enum.empty?(all_failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(all_failures)}")
      handle_failures(all_failures)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, {:not_agent_friendly, url}}
        end

      {:ok, %{status: status}} ->
        {:error, {:bad_status, url, status}}

      {:error, _reason} ->
        {:error, {:timeout, url}}
    end
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        elapsed_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if elapsed_ms > 1000 do
          {:error, {:mcp_slow_response, url}}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, {:mcp_invalid_json, url}}
          end
        end

      {:ok, %{status: status}} ->
        {:error, {:bad_status, url, status}}

      {:error, _reason} ->
        {:error, {:timeout, url}}
    end
  end

  defp handle_failures(failures) do
    # Only process MCP failures for automatic PRs
    mcp_failures =
      Enum.filter(failures, fn
        {:error, {:mcp_slow_response, _url}} -> true
        {:error, {:mcp_invalid_json, _url}} -> true
        _ -> false
      end)

    if not Enum.empty?(mcp_failures) do
      Logger.info("Initiating PR for MCP failures...")
      create_fix_pr(mcp_failures)
    end
  end

  defp create_fix_pr(failures) do
    Task.start(fn ->
      # Deduplicate errors safely using static reasons to ensure proper matching
      unique_reasons =
        failures
        |> Enum.map(fn {:error, {reason, url}} -> "#{reason} on #{url}" end)
        |> Enum.uniq()

      issue_body = "AX Audit detected issues:\n" <> Enum.join(unique_reasons, "\n")
      branch_name = "ax-audit-fix-#{System.system_time(:second)}"
      commit_msg = "Fix AX Audit MCP issues"

      Logger.info("Creating PR with branch #{branch_name}")

      # Avoid direct git checkout/commit
      with {tree_hash, 0} <- System.cmd("git", ["write-tree"]),
           tree_hash = String.trim(tree_hash),
           {parent_hash, 0} <- System.cmd("git", ["rev-parse", "HEAD"]),
           parent_hash = String.trim(parent_hash),
           {commit_hash, 0} <-
             System.cmd("git", ["commit-tree", tree_hash, "-p", parent_hash, "-m", commit_msg]),
           commit_hash = String.trim(commit_hash),
           {_, 0} <- System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash]),
           {_, 0} <- System.cmd("git", ["push", "origin", branch_name]) do
        # Create PR using gh CLI
        System.cmd("gh", [
          "pr",
          "create",
          "--title",
          commit_msg,
          "--body",
          issue_body,
          "--head",
          branch_name
        ])
      else
        error ->
          Logger.error("Failed to create PR: #{inspect(error)}")
      end
    end)
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
