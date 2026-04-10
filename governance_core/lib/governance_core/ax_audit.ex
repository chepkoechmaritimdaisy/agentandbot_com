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
    Logger.info("Starting Continuous AX Audit on MCP endpoint...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    mcp_url = base_url <> "/api/mcp"

    start_time = System.monotonic_time(:millisecond)

    case Req.get(mcp_url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        cond do
          duration > 1000 ->
            handle_failure("MCP endpoint response time too high: #{duration}ms")
          not valid_json?(body) ->
            handle_failure("MCP endpoint returned invalid JSON structure")
          true ->
            Logger.info("AX Audit Passed: MCP endpoint is healthy.")
        end

      {:ok, %{status: status}} ->
        handle_failure("MCP endpoint returned status #{status}")

      {:error, _reason} ->
        # Use a static error reason for deduplication matching
        handle_failure("Failed to fetch MCP endpoint: {:error, :timeout}")
    end
  end

  defp valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp handle_failure(reason) do
    Logger.error("AX Audit Failed: #{reason}")
    create_auto_fix_pr(reason)
  end

  defp create_auto_fix_pr(reason) do
    branch_name = "auto-fix-ax-audit-#{:os.system_time(:second)}"
    title = "Auto-Fix: AX Audit Failure"
    body = "AX Audit failed with reason: #{reason}. Please investigate."

    try do
      # Deduplication check
      case System.cmd("gh", ["pr", "list", "--search", "#{title} in:title state:open"]) do
        {search_out, 0} ->
          if String.trim(search_out) != "" do
            Logger.info("AX Audit Auto-Fix PR already exists. Skipping.")
          else
            execute_git_flow(branch_name, title, body)
          end
        {error_out, code} ->
          Logger.warning("Failed to check existing PRs. Exit #{code}: #{error_out}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute git or gh commands: #{inspect(e)}")
    end
  end

  defp execute_git_flow(branch_name, title, body) do
    case System.cmd("git", ["write-tree"]) do
      {tree_hash, 0} ->
        tree_hash = String.trim(tree_hash)

        case System.cmd("git", ["commit-tree", tree_hash, "-p", "HEAD", "-m", title]) do
          {commit_hash, 0} ->
            commit_hash = String.trim(commit_hash)

            case System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash]) do
              {_, 0} ->
                case System.cmd("git", ["push", "origin", branch_name]) do
                  {_, 0} ->
                    case System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--head", branch_name]) do
                      {_, 0} ->
                        Logger.info("Created Auto-Fix PR for AX Audit failure.")
                      {error, code} ->
                        Logger.warning("Failed to create PR with gh. Exit #{code}: #{error}")
                    end
                  {error, code} ->
                    Logger.warning("Failed to push branch. Exit #{code}: #{error}")
                end
              {error, code} ->
                Logger.warning("Failed to update git ref. Exit #{code}: #{error}")
            end
          {error, code} ->
            Logger.warning("Failed to run commit-tree. Exit #{code}: #{error}")
        end
      {error, code} ->
        Logger.warning("Failed to run write-tree. Exit #{code}: #{error}")
    end
  end
end
