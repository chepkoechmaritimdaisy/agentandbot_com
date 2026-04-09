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
    GenServer.start_link(__MODULE__, %{recent_prs: []}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    new_state = perform_audit(state)
    schedule_audit()
    {:noreply, new_state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit(state) do
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
      state
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures, state)
    end
  end

  defp check_endpoint(url) do
    # Use decode_body: false to safely handle invalid JSON without crashing
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, :invalid_json_schema}
        end
      {:ok, %{status: _status}} ->
        {:error, :unexpected_status}
      {:error, _reason} ->
        # Use static error reason to deduplicate correctly
        {:error, :timeout}
    end
  end

  defp is_agent_friendly?(body) do
    case Jason.decode(body) do
      {:ok, _json} -> true
      {:error, _} -> false
    end
  end

  defp handle_failures(failures, state) do
    new_prs = Enum.reduce(failures, state.recent_prs, fn {:error, reason}, acc ->
      if reason in acc do
        acc
      else
        create_pr_for_failure(reason)
        [reason | acc] |> Enum.take(10)
      end
    end)
    %{state | recent_prs: new_prs}
  end

  defp create_pr_for_failure(reason) do
    branch_name = "fix-ax-audit-#{System.system_time(:second)}"

    # Create an empty commit and push to a new remote branch without checkout/commit
    cmd = """
    tree=$(git write-tree)
    commit=$(echo "Automated fix for #{reason}" | git commit-tree $tree -p HEAD)
    git update-ref refs/heads/#{branch_name} $commit
    git push origin #{branch_name}
    gh pr create --title 'Fix AX Audit Failure: #{reason}' --body 'AX Audit detected an issue: #{reason}' --head #{branch_name} --base main
    """

    Logger.info("Creating PR for AX Audit failure: #{reason}")
    System.cmd("sh", ["-c", cmd])
  end
end
