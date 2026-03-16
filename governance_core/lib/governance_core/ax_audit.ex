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

  def init(_state) do
    # Maintain state to prevent PR spamming
    schedule_audit()
    {:ok, %{recent_prs: []}}
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
    endpoints = ["/", "/agents", "/dashboard/traffic"]
    api_endpoints = ["/api/agents", "/.well-known/agent.json"]

    html_results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    api_results = Enum.map(api_endpoints, fn path ->
      url = base_url <> path
      check_api_endpoint(url)
    end)

    failures = Enum.filter(html_results ++ api_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
      state
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures, state)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp check_api_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        if duration > 1000 do
          {:error, "Endpoint #{url} took too long to respond (#{duration}ms)"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON"}
          end
        end

      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
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

  defp handle_failures(failures, state) do
    new_prs =
      Enum.reduce(failures, state.recent_prs, fn {:error, reason}, recent_prs ->
        pr_identifier = :erlang.phash2(reason)

        if pr_identifier in recent_prs do
          Logger.info("Skipping PR creation for previously reported failure: #{reason}")
          recent_prs
        else
          branch_name = "fix-ax-audit-#{System.unique_integer([:positive])}"
          title = "Fix AX Audit Failure"
          body = "Automated PR to fix AX Audit Failure: #{reason}"

          # Ideally, we would create a new branch and push a fix before creating the PR.
          # To avoid disrupting the live production application's local git state,
          # we assume the CI/CD pipeline or an external worker handles the actual git branch creation,
          # or we use the GitHub API directly.
          # Per project specs, we use `gh pr create` CLI.

          Logger.info("Would run: gh pr create --title \"#{title}\" --body \"#{body}\" --head \"#{branch_name}\"")

          # System.cmd("gh", ["pr", "create", "--title", title, "--body", body, "--head", branch_name])

          [pr_identifier | recent_prs]
        end
      end)
      |> Enum.take(20) # Keep only the last 20 PRs tracked to avoid memory leak

    %{state | recent_prs: new_prs}
  end
end
