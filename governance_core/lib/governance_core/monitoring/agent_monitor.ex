defmodule GovernanceCore.Monitoring.AgentMonitor do
  use GenServer
  require Logger

  @check_interval 60_000 # 60 seconds

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    Logger.info("Starting AgentMonitor (AX Watchdog)...")
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_endpoints, state) do
    endpoints = Application.get_env(:governance_core, :monitored_endpoints, default_endpoints())
    Task.start(fn -> run_checks(endpoints) end)
    schedule_check()
    {:noreply, state}
  end

  defp default_endpoints do
    [
      {"http://localhost:4000/api/health", "Core Health"},
      {"http://localhost:4000/api/v1/skills", "Skills API"}
    ]
  end

  defp schedule_check do
    Process.send_after(self(), :check_endpoints, @check_interval)
  end

  defp run_checks(endpoints) do
    for {url, name} <- endpoints do
      check_endpoint(url, name)
    end
  end

  defp check_endpoint(url, name) do
    start_time = System.monotonic_time(:millisecond)

    # Use Req as per project guidelines
    case Req.get(url, connect_options: [timeout: 5000], retry: false) do
      {:ok, %{status: 200, body: body}} ->
        latency = System.monotonic_time(:millisecond) - start_time

        cond do
          latency > 500 ->
            Logger.warning("[AX Alert] #{name} response slow: #{latency}ms")

          not validate_schema(body) ->
            Logger.error("[AX Schema Error] #{name} returned invalid JSON schema: #{inspect(body)}")

          true ->
            Logger.debug("[AX OK] #{name} responded in #{latency}ms")
        end

      {:ok, %{status: status}} ->
        Logger.error("[AX Failure] #{name} returned status #{status}")

      {:error, exception} ->
        # Log error but don't crash, it's expected if server is down
        Logger.error("[AX Error] #{name} check failed: #{inspect(exception)}")
    end
  end

  defp validate_schema(body) when is_map(body), do: true
  defp validate_schema(_), do: false
end
