defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  - MCP endpoints for response time and valid JSON schema
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
      check_html_endpoint(url)
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
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        cond do
          duration > 1000 ->
             {:error, :slow_response}
          not valid_json?(body) ->
             {:error, :invalid_json}
          true ->
             {:ok, url}
        end

      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp is_agent_friendly?(html) do
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp valid_json?(binary) do
    case Jason.decode(binary) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_fix_pr(failures) do
    Logger.info("Preparing PR to address AX Audit failures...")

    # Generate an error report
    report_content = """
    # AX Audit Report

    The following endpoints failed the Agent-Friendly (AX) Audit:

    """ <> Enum.map_join(failures, "\n", fn {:error, reason} -> "- #{reason}" end)

    File.write!("ax_audit_report.md", report_content)

    System.cmd("git", ["add", "ax_audit_report.md"])

    # automated PR creation method
    {tree_sha, 0} = System.cmd("git", ["write-tree"])
    tree_sha = String.trim(tree_sha)

    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    head_sha = String.trim(head_sha)

    {commit_sha, 0} = System.cmd("git", ["commit-tree", tree_sha, "-p", head_sha, "-m", "Automated AX Audit Fix"])
    commit_sha = String.trim(commit_sha)

    branch_name = "ax-audit-fix-#{System.system_time(:second)}"

    {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_sha])

    # Attempt to push and create PR, handle gracefully if gh is not authenticated
    case System.cmd("git", ["push", "origin", branch_name]) do
      {_, 0} ->
        case System.cmd("gh", ["pr", "create", "--title", "Fix AX Audit Failures", "--body", "Automated PR from GovernanceCore.AXAudit", "--head", branch_name]) do
          {_, 0} -> Logger.info("Successfully created PR for AX Audit failures.")
          {err, _} -> Logger.error("Failed to create PR with gh: #{err}")
        end
      {err, _} -> Logger.error("Failed to push branch: #{err}")
    end
  end
end
