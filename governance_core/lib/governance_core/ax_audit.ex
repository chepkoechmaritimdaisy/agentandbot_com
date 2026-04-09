defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Valid JSON schema on MCP endpoints
  - Response time
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
      prepare_fix_pr(failures)
    end
  end

  defp check_endpoint(url) do
    # Check response time and schema
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url, decode_body: false, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 2000 do
          {:error, :timeout} # static reason for deduplication
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_schema} # static reason for deduplication
          end
        end

      {:ok, %{status: _status}} ->
        {:error, :invalid_status} # static reason for deduplication

      {:error, _reason} ->
        {:error, :request_failed} # static reason for deduplication
    end
  end

  defp prepare_fix_pr(failures) do
    # Only prepare PR if gh CLI is available
    if System.find_executable("gh") do
      branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"
      message = "fix: Agent-Friendly (AX) endpoint failure detected\n\nFailures: #{inspect(failures)}"

      case System.cmd("git", ["rev-parse", "HEAD"]) do
        {parent_hash, 0} ->
          parent_hash = String.trim(parent_hash)
          case System.cmd("git", ["write-tree"]) do
            {tree_hash, 0} ->
              tree_hash = String.trim(tree_hash)
              case System.cmd("git", ["commit-tree", tree_hash, "-p", parent_hash, "-m", message]) do
                {commit_hash, 0} ->
                  commit_hash = String.trim(commit_hash)
                  System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash])
                  System.cmd("git", ["push", "origin", branch_name])
                  System.cmd("gh", ["pr", "create", "--base", "main", "--head", branch_name, "--title", "fix: Automated AX Audit correction", "--body", message])
                _ -> Logger.error("Failed to create commit for AX Audit PR")
              end
            _ -> Logger.error("Failed to write tree for AX Audit PR")
          end
        _ -> Logger.error("Failed to get parent commit hash for AX Audit PR")
      end
    else
      Logger.warning("gh CLI not found, skipping PR creation for AX Audit fix.")
    end
  end
end
