defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Agent JSON schema format at `/.well-known/agent.json`
  - `/api/agents` endpoint performance and response validity
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
      report_failure(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time()

    case Req.get(url, decode_body: false, receive_timeout: 5000) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        # Ensure response time is under 1 second (1000 ms)
        response_time_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        if response_time_ms > 1000 do
            {:error, "Endpoint #{url} response time too slow: #{response_time_ms}ms"}
        else
            if is_valid_json_schema?(body) do
                {:ok, url}
            else
                {:error, "Endpoint #{url} returned invalid JSON schema"}
            end
        end

      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}

      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp is_valid_json_schema?(body) do
      case Jason.decode(body) do
        {:ok, decoded} when is_map(decoded) or is_list(decoded) -> true
        _ -> false
      end
  end

  defp report_failure(failures) do
      failure_details =
        Enum.map(failures, fn {:error, reason} -> "- #{reason}" end)
        |> Enum.join("\n")

      title = "AX Audit Failure"
      body = "The automated AX Audit detected the following issues:\n\n#{failure_details}"

      System.cmd("gh", ["issue", "create", "--title", title, "--body", body, "--label", "ax-audit"])
      Logger.info("Opened GitHub issue for AX Audit failures.")
  end
end
