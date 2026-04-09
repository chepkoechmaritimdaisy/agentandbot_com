defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker Swarm or K3s containers for resource
  limits (CPU/RAM). It logs warnings for containers exceeding usage or
  at risk of OOM Kill.
  """

  use GenServer
  require Logger

  @interval 30_000 # 30 seconds

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @interval)
    schedule_check(interval)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:check_resources, state) do
    Logger.debug("Starting Resource Watchdog check...")
    check_docker_stats()
    schedule_check(state.interval)
    {:noreply, state}
  end

  defp schedule_check(interval) do
    Process.send_after(self(), :check_resources, interval)
  end

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_log_stats(output)

        {error_output, exit_code} ->
          Logger.warning("Docker stats command failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      # System.cmd throws an ErlangError if the executable is not found
      e in ErlangError ->
        Logger.error("ResourceWatchdog could not execute docker command: #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    output
    |> String.split("\\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu, mem] ->
          check_limits(name, cpu, mem)

        _ ->
          Logger.debug("Unparseable docker stat line: #{line}")
      end
    end)
  end

  defp check_limits(name, cpu, mem) do
    # Simple check example: if CPU is above 90% or RAM is high (e.g., matching GiB usage context)
    # This logic can be more robust for production.
    if String.contains?(cpu, ["9", "100"]) do
      Logger.warning("ResourceWatchdog: Container #{name} is using high CPU: #{cpu}")
    end

    if String.contains?(mem, "GiB") do
      Logger.warning("ResourceWatchdog: Container #{name} has high memory usage: #{mem} (OOM risk)")
    end
  end
end
