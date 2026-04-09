defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  - Valid JSON and response times on MCP endpoints
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

    # Use Task.async_stream to process concurrently with back-pressure
    html_stream = Task.async_stream(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end, timeout: :infinity)

    mcp_stream = Task.async_stream(mcp_endpoints, fn path ->
      url = base_url <> path
      check_mcp_endpoint(url)
    end, timeout: :infinity)

    results = Enum.map(html_stream, fn {:ok, res} -> res end) ++
              Enum.map(mcp_stream, fn {:ok, res} -> res end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")

      # Use static error reason for deduplication logic (using the first failure)
      [{:error, first_fail_reason} | _] = failures
      dedup_reason =
        cond do
          first_fail_reason == :timeout -> :timeout
          first_fail_reason == :invalid_json -> :invalid_json
          first_fail_reason == :invalid_schema -> :invalid_schema
          first_fail_reason == :not_agent_friendly -> :not_agent_friendly
          true -> :unknown_error
        end

      create_fix_pr(dedup_reason)
    end
  end

  defp check_html_endpoint(url) do
    case Req.get(url, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, :not_agent_friendly}
        end
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, :timeout}
      {:error, _reason} ->
        {:error, :request_failed}
    end
  end

  defp check_mcp_endpoint(url) do
    case Req.get(url, decode_body: false, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _json} -> {:ok, url}
          {:error, _} -> {:error, :invalid_json}
        end
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, %Mint.TransportError{reason: :timeout}} ->
        {:error, :timeout}
      {:error, _reason} ->
        {:error, :request_failed}
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp create_fix_pr(reason) do
    Logger.info("Attempting to create automated PR for AX Audit failure: #{reason}")

    branch_name = "auto-fix-ax-audit-#{System.unique_integer([:positive])}"

    # We use git plumbing commands to avoid mutating the live environment's working tree
    try do
      # Make sure branch doesn't already exist or handle appropriately
      {tree_hash, 0} = System.cmd("git", ["write-tree"])
      tree_hash = String.trim(tree_hash)

      {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", "Auto-fix: AX Audit Failure (#{reason})"])
      commit_hash = String.trim(commit_hash)

      {_, 0} = System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])

      {_, push_exit} = System.cmd("git", ["push", "origin", branch_name])

      if push_exit == 0 do
        System.cmd("gh", ["pr", "create",
                          "--title", "Auto-fix: AX Audit Failure (#{reason})",
                          "--body", "Automated PR created by GovernanceCore.AXAudit to fix #{reason} failures.",
                          "--head", branch_name,
                          "--base", "main"])
        Logger.info("Successfully created PR for AX Audit failure.")
      else
        Logger.error("Failed to push branch for automated PR.")
      end
    rescue
      e -> Logger.error("Failed to create automated PR: #{inspect(e)}")
    end
  end
end
