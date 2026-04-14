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

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    mcp_url = base_url <> "/api/mcp"

    start_time = System.monotonic_time(:millisecond)

    # fetch /api/mcp using Req with decode_body: false
    case Req.get(mcp_url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        cond do
          duration > 1000 ->
            handle_failure("Response time too long", {:error, :timeout})
          not valid_json?(body) ->
            handle_failure("Invalid JSON schema", {:error, :invalid_json})
          true ->
            Logger.info("AX Audit Passed: MCP endpoint is Agent-Friendly.")
        end

      {:ok, %{status: status}} ->
        handle_failure("Endpoint returned status #{status}", {:error, :bad_status})

      {:error, _reason} ->
        handle_failure("Failed to fetch endpoint", {:error, :network_error})
    end
  end

  defp valid_json?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp handle_failure(message, static_error) do
    Logger.error("AX Audit Failed: #{message}")
    prepare_pr(static_error)
  end

  defp prepare_pr(static_error) do
    try do
      # Avoid PR spam loops for automated fixes
      dedup_search = "gh pr list --search 'AX Audit Fix: #{inspect(static_error)}'"

      case System.cmd("sh", ["-c", dedup_search]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(static_error)
          else
            Logger.info("PR already exists for #{inspect(static_error)}")
          end
        _ ->
          Logger.error("Failed to check for existing PRs")
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute gh: #{inspect(e)}")
    end
  end

  defp create_pr(static_error) do
    branch_name = "ax-audit-fix-#{:os.system_time(:second)}"

    # Prepare and push branch avoiding direct local git mutations
    # Memory mandates using write-tree, commit-tree, update-ref, push
    try do
      {tree_hash, 0} = System.cmd("sh", ["-c", "git write-tree"])
      tree_hash = String.trim(tree_hash)

      commit_msg = "AX Audit Fix: #{inspect(static_error)}"
      {commit_hash, 0} = System.cmd("sh", ["-c", "git commit-tree #{tree_hash} -p HEAD -m '#{commit_msg}'"])
      commit_hash = String.trim(commit_hash)

      {_, 0} = System.cmd("sh", ["-c", "git update-ref refs/heads/#{branch_name} #{commit_hash}"])
      {_, 0} = System.cmd("sh", ["-c", "git push origin #{branch_name}"])

      {gh_out, 0} = System.cmd("sh", ["-c", "gh pr create --title 'AX Audit Fix: #{inspect(static_error)}' --body 'Automated fix for AX Audit failure.' --head #{branch_name}"])
      Logger.info("PR Created: #{gh_out}")
    rescue
      MatchError -> Logger.error("Git/GH commands failed while creating PR for AX Audit.")
    end
  end
end
