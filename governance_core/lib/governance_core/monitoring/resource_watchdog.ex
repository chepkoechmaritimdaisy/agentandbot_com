defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Automated GenServer to monitor container CPU and RAM usage via docker stats.
  Logs warnings for containers exceeding resource quotas.
  """

  use GenServer
  require Logger

  # Default interval: 30 seconds
  @interval 30_000

  # Example thresholds
  @cpu_threshold 80.0
  @mem_threshold 80.0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {error_output, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: docker executable not found or failed to run. ErlangError: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu_str, mem_str] ->
          cpu = parse_percent(cpu_str)
          mem = parse_percent(mem_str)

          if cpu > @cpu_threshold do
            Logger.warning("ResourceWatchdog: Container #{name} exceeds CPU threshold (#{@cpu_threshold}%): #{cpu}%")
          end

          if mem > @mem_threshold do
            Logger.warning("ResourceWatchdog: Container #{name} exceeds Memory threshold (#{@mem_threshold}%): #{mem}%")
          end

        _ ->
          Logger.warning("ResourceWatchdog: Could not parse docker stats line: #{line}")
      end
    end)
  end

  defp parse_percent(str) do
    str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
