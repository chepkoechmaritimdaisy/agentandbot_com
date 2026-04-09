defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - MCP endpoints response times
  - Valid JSON schema on endpoints
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  @timeout 500

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
    endpoints = ["/api/agents", "/.well-known/agent.json"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All MCP endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        elapsed_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if elapsed_ms > @timeout do
          {:error, :timeout}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_json}
          end
        end

      {:ok, %{status: status}} ->
        {:error, :invalid_status}

      {:error, _reason} ->
        {:error, :network_error}
    end
  end

  defp handle_failures(failures) do
    deduped_failures = failures |> Enum.uniq_by(fn {_status, reason} -> reason end)

    Enum.each(deduped_failures, fn {:error, reason} ->
      create_pr_for_failure(reason)
    end)
  end

  defp create_pr_for_failure(reason) do
    Logger.info("Creating PR for AX Audit failure: #{inspect(reason)}")

    branch_name = "ax-audit-fix-#{System.system_time(:second)}"
    title = "🤖 AX Audit Fix: #{reason}"
    body = "Automated PR created by AX Audit due to #{reason} failure on MCP endpoints."

    try do
      # Create tree
      {tree_hash, 0} = System.cmd("git", ["write-tree"])
      tree_hash = String.trim(tree_hash)

      # Create commit
      {commit_hash, 0} = System.cmd("git", ["commit-tree", tree_hash, "-m", title])
      commit_hash = String.trim(commit_hash)

      # Create branch
      {_, 0} = System.cmd("git", ["update-ref", "refs/heads/" <> branch_name, commit_hash])

      # Push branch
      {_, 0} = System.cmd("git", ["push", "-u", "origin", branch_name])

      # Create PR
      {_, 0} = System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--head", branch_name])
    rescue
      e -> Logger.error("Failed to create PR: #{inspect(e)}")
    end
  end
end
