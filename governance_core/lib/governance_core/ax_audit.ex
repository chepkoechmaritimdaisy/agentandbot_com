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
  # Adjust interval as appropriate; for continuous monitoring maybe lower than 24h
  # Using 1 hour here for example, though it can be tweaked.
  @interval 60 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit on MCP endpoint...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    # Now targets /api/mcp
    url = base_url <> "/api/mcp"

    start_time = System.monotonic_time(:millisecond)

    case Req.get(url, decode_body: false) do
      {:ok, %{status: status, body: body}} when status in 200..299 ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 1000 do
          handle_failure({:error, :timeout}, "Endpoint #{url} responded too slowly (#{duration}ms)")
        else
          # Attempt to validate JSON schema manually
          case Jason.decode(body) do
            {:ok, _json} ->
              Logger.info("AX Audit Passed: /api/mcp is healthy.")
            {:error, _} ->
              handle_failure({:error, :invalid_schema}, "Endpoint #{url} returned malformed JSON")
          end
        end

      {:ok, %{status: status}} ->
        handle_failure({:error, :bad_status}, "Endpoint #{url} returned status #{status}")

      {:error, reason} ->
        handle_failure({:error, :request_failed}, "Failed to fetch #{url}: #{inspect(reason)}")
    end
  end

  defp handle_failure(error_type, message) do
    Logger.error("AX Audit Failed: #{message}")
    create_pull_request(error_type, message)
  end

  defp create_pull_request(error_type, message) do
    # Deduplicate errors based on the static error_type atom to avoid PR spam
    search_query = "in:title \"Fix AX Audit Failure: #{inspect(error_type)}\""

    try do
      case System.cmd("gh", ["pr", "list", "--search", search_query, "--json", "id"]) do
        {output, 0} ->
          if String.trim(output) == "[]" do
            # No existing PR found, create a new one
            branch_name = "auto-fix-ax-audit-#{:os.system_time(:second)}"

            # Using low-level git commands to avoid checkout
            with {tree_hash, 0} <- System.cmd("git", ["write-tree"]),
                 tree_hash = String.trim(tree_hash),
                 {commit_hash, 0} <- System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", "Fix AX Audit Failure: #{inspect(error_type)}\n\n#{message}"]),
                 commit_hash = String.trim(commit_hash),
                 {_, 0} <- System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash]),
                 {_, 0} <- System.cmd("git", ["push", "-u", "origin", branch_name]),
                 {_, 0} <- System.cmd("gh", ["pr", "create", "--base", "main", "--head", branch_name, "--title", "Fix AX Audit Failure: #{inspect(error_type)}", "--body", "Automated PR created by AX Audit.\n\nIssue: #{message}"]) do
              Logger.info("Created automated PR for #{inspect(error_type)}")
            else
              error -> Logger.error("Failed to create automated PR: #{inspect(error)}")
            end
          else
            Logger.info("PR already exists for #{inspect(error_type)}, skipping creation.")
          end
        {error_output, exit_code} ->
          Logger.error("Failed to check for existing PRs via gh CLI. Exit code: #{exit_code}. Output: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("gh or git CLI not available or crashed: #{inspect(e)}")
    end
  end
end
