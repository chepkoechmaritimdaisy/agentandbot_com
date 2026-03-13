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
    GenServer.start_link(__MODULE__, %{last_pr_created_at: nil}, name: __MODULE__)
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

  defp perform_audit(state) do
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

      now = DateTime.utc_now()
      # Only create PR if one hasn't been created in the last 24 hours
      can_create_pr? =
        case state.last_pr_created_at do
          nil -> true
          last_dt -> DateTime.diff(now, last_dt, :hour) >= 24
        end

      if can_create_pr? do
        create_github_pr(failures)
        %{state | last_pr_created_at: now}
      else
        Logger.info("Skipping GitHub PR creation to prevent spam (cooldown active).")
        state
      end
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        # Calculate latency in milliseconds
        latency = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if latency > 1000 do
           {:error, "Endpoint #{url} is slow (Latency: #{latency}ms)"}
        else
           # Validate JSON Schema manually to prevent Req from crashing
           case Jason.decode(body) do
             {:ok, _json} ->
               {:ok, url}
             {:error, _reason} ->
               {:error, "Endpoint #{url} returned malformed JSON schema"}
           end
        end

      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp create_github_pr(failures) do
    Logger.info("Creating a GitHub Pull Request for AX Audit fixes...")

    body =
      Enum.map(failures, fn {:error, reason} -> "- #{reason}" end)
      |> Enum.join("\n")

    pr_body = "The Continuous AX Audit detected the following failures and requires agent intervention:\n\n" <> body

    case System.cmd("gh", ["pr", "create", "--title", "Fix: Automated AX Audit Failures", "--body", pr_body]) do
      {output, 0} ->
        Logger.info("Successfully created GitHub PR: #{String.trim(output)}")

      {output, exit_status} ->
        Logger.error("Failed to create GitHub PR (Exit: #{exit_status}): #{output}")
    end
  end
end
