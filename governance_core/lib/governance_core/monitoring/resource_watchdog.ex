defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the CPU and RAM usage of running agent containers.
  It utilizes docker stats via System.cmd dynamically.
  """
  use GenServer
  require Logger

  # Poll every 60 seconds
  @interval 60_000
  @cpu_limit 80.0
  @mem_limit 80.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_poll()
    {:ok, state}
  end

  def handle_info(:poll, state) do
    perform_check()
    schedule_poll()
    {:noreply, state}
  end

  defp schedule_poll do
    Process.send_after(self(), :poll, @interval)
  end

  def perform_check do
    Logger.info("Resource Watchdog: Checking container usage...")

    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}"]) do
      {output, 0} ->
        parse_and_evaluate(output)

      {error_output, status} ->
        Logger.error("Resource Watchdog: Failed to run docker stats. Status: #{status}. Output: #{error_output}")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      case String.split(line, "\t") do
        [name, cpu_perc, mem_perc] ->
          cpu_val = parse_perc(cpu_perc)
          mem_val = parse_perc(mem_perc)

          if cpu_val > @cpu_limit do
            Logger.warning("Container #{name} CPU usage is critically high: #{cpu_val}%")
          end

          if mem_val > @mem_limit do
            Logger.warning("Container #{name} RAM usage is critically high (OOM risk): #{mem_val}%")
          end

        _ ->
          Logger.error("Resource Watchdog: Malformed docker stats output line: #{line}")
      end
    end)
  end

  defp parse_perc(perc_string) do
    perc_string
    |> String.trim("%")
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
