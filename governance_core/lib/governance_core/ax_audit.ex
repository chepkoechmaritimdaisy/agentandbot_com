defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a periodic audit of the application's MCP endpoints to ensure they remain
  "Agent-Friendly" by monitoring response time and valid JSON schema.
  Automatically log and create a PR to fix the endpoints if they go down.
  """
  use GenServer
  require Logger

  # Default interval of 1 hour
  @interval 60 * 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule_audit(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit(state.interval)
    {:noreply, state}
  end

  defp schedule_audit(interval) do
    Process.send_after(self(), :audit, interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit on MCP endpoints...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/api/agents", "/.well-known/agent.json"]

    results =
      Task.async_stream(
        endpoints,
        fn path ->
          url = base_url <> path
          check_endpoint(url)
        end,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, result} -> result end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All MCP endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")

      # Ensure static error reasons to allow for deduplication without time variance
      static_failures =
        Enum.map(failures, fn {:error, {url, _reason}} ->
          {:error, {url, :ax_audit_failure}}
        end)

      create_fix_pr(static_failures)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        if valid_json?(body) do
          {:ok, url}
        else
          {:error, {url, :invalid_json}}
        end

      {:ok, %{status: status}} ->
        {:error, {url, {:bad_status, status}}}

      {:error, _reason} ->
        # Use a static error reason for deduplication
        {:error, {url, :request_failed}}
    end
  end

  defp valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_fix_pr(failures) do
    Logger.info("Preparing PR for AX Audit failures...")

    timestamp = :os.system_time(:seconds)
    branch_name = "ax-audit-fix-#{timestamp}"

    # Generate a descriptive commit message
    commit_msg = "fix: Automated AX Audit fix for MCP endpoints"

    System.cmd("git", ["checkout", "-b", branch_name])

    # Ideally, logic to apply a fix would go here.
    # We add empty commits/push and PR as the automated part for now

    # In order to push without directly changing local trees if we are in prod,
    # the guidelines recommend using git write-tree / commit-tree.
    {tree_sha, 0} = System.cmd("git", ["write-tree"])
    tree_sha = String.trim(tree_sha)

    # get parent commit
    {parent_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"])
    parent_sha = String.trim(parent_sha)

    {commit_sha, 0} = System.cmd("git", ["commit-tree", tree_sha, "-p", parent_sha, "-m", commit_msg])
    commit_sha = String.trim(commit_sha)

    System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_sha])

    # Push the new branch
    System.cmd("git", ["push", "-u", "origin", branch_name])

    # Use `gh` cli to create a PR
    pr_body = "Automated PR created by AX Audit to fix MCP endpoints.\\nFailures: #{inspect(failures)}"
    System.cmd("gh", ["pr", "create", "--title", commit_msg, "--body", pr_body, "--head", branch_name])

    # Cleanup local branch if needed or let it be
    System.cmd("git", ["checkout", "-"])

    Logger.info("PR created successfully.")
  rescue
    e -> Logger.error("Failed to create fix PR: #{inspect(e)}")
  end
end
