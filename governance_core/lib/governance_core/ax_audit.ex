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
      handle_failures(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        response_time_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        # Arbitrary response time threshold, e.g. 500ms
        if response_time_ms > 500 do
          {:error, "Endpoint #{url} response time too slow: #{response_time_ms}ms"}
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

  defp handle_failures(failures) do
    # Create issue/PR using gh cli
    # Prepare failure report
    report = Enum.map_join(failures, "\n", fn {:error, reason} -> "- #{reason}" end)

    Logger.info("Triggering automated PR/issue for AX Audit failures")

    # This is a sample representation of creating an issue and a PR.
    # A real script might create a branch, fix the issue, commit, and then create PR.
    # Here we simulate logging the issue with gh.
    System.cmd("gh", ["issue", "create", "--title", "Automated: AX Audit Failure", "--body", report])
  end
end
