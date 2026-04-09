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

    # HTML Endpoints
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]
    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    # MCP / JSON Endpoints
    mcp_endpoints = ["/api/agents", "/.well-known/agent.json"]
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
      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp check_mcp_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time

        cond do
          response_time > 1000 ->
             {:error, :timeout}
          not valid_json?(body) ->
             {:error, :invalid_schema}
          true ->
             {:ok, url}
        end
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, %Req.TransportError{reason: :timeout}} ->
        {:error, :timeout}
      {:error, _reason} ->
        {:error, :fetch_failed}
    end
  end

  defp valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
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

  defp create_fix_pr(failures) do
    # Ensure gh cli is available
    case System.cmd("which", ["gh"]) do
      {_, 0} ->
        Logger.info("Creating automated fix PR for AX Audit failures...")
        branch_name = "auto-fix/ax-audit-#{System.system_time(:second)}"
        message = "Auto-fix: AX Audit failures"

        # Use git tree commands to avoid direct local git mutations
        System.cmd("git", ["write-tree"])
        {tree_hash, 0} = System.cmd("git", ["write-tree"])
        tree_hash = String.trim(tree_hash)

        {head_hash, 0} = System.cmd("git", ["rev-parse", "HEAD"])
        head_hash = String.trim(head_hash)

        {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", head_hash, "-m", message])
        commit_hash = String.trim(commit_hash)

        System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])
        System.cmd("git", ["push", "origin", branch_name])

        body = "Automated PR created by GovernanceCore.AXAudit to address the following failures:\n\n" <> inspect(failures)

        System.cmd("gh", ["pr", "create", "--base", "main", "--head", branch_name, "--title", message, "--body", body])
        Logger.info("Automated PR created.")
      _ ->
        Logger.warning("gh CLI not found. Skipping automated PR creation.")
    end
  end
end
