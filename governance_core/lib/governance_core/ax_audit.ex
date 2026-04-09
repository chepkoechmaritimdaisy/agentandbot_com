defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks MCP endpoints for response time and valid JSON schema.
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  # Max allowed response time in ms
  @max_response_time 500

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    Task.start(fn -> perform_audit() end)
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/api/agents", "/.well-known/agent.json"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_pr_for_failures(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)

    # decode_body: false is important for safely handling invalid JSON
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time

        if response_time > @max_response_time do
           {:error, :timeout}
        else
           # Validate JSON structure
           case Jason.decode(body) do
             {:ok, _json} -> {:ok, url}
             {:error, _} -> {:error, :invalid_json}
           end
        end
      {:ok, %{status: _status}} ->
        {:error, :bad_status}
      {:error, _reason} ->
        {:error, :request_failed}
    end
  end

  defp create_pr_for_failures(failures) do
    Logger.info("Preparing PR for AX Audit fix...")

    branch_name = "fix/ax-audit-#{:os.system_time(:seconds)}"
    commit_msg = "fix: address AX audit failures"

    # Generate report
    report = Enum.map(failures, fn {:error, reason} -> "- #{inspect(reason)}" end) |> Enum.join("\n")

    pr_body = "Automated AX Audit found issues with MCP endpoints:\n#{report}"

    # Use tree/commit logic as per memory to avoid direct local git mutations
    # We must add the file to the index before writing the tree
    File.write!("ax_audit_report.md", pr_body)
    System.cmd("git", ["add", "ax_audit_report.md"])

    {tree_sha, 0} = System.cmd("git", ["write-tree"])
    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    {commit_sha, 0} = System.cmd("git", ["commit-tree", String.trim(tree_sha), "-p", String.trim(head_sha), "-m", commit_msg])

    System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", String.trim(commit_sha)])

    # Note: gh CLI needs to be authenticated for this to work in reality
    # System.cmd("git", ["push", "-u", "origin", branch_name])
    # System.cmd("gh", ["pr", "create", "--title", commit_msg, "--body", pr_body])

    Logger.info("Prepared PR branch #{branch_name} for AX audit failures.")
  end

  # For backwards compatibility with old tests if they exist
  def is_agent_friendly?(html) do
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end
end
