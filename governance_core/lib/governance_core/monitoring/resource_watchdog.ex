defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of agent containers running on Docker Swarm or K3s.
  """
  use GenServer
  require Logger

  # Check every 1 minute
  @interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_resources do
    try do
      # docker stats --no-stream --format "{{.Name}}: {{.CPUPerc}}, {{.MemUsage}}"
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          process_stats(output)
        {error_output, exit_code} ->
          Logger.warning("Docker stats command failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run docker stats (binary might be missing): #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    output
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu_perc, mem_perc] ->
          cpu_val = parse_percentage(cpu_perc)
          mem_val = parse_percentage(mem_perc)

          if cpu_val > 80.0 do
            Logger.warning("Resource Alert: Container #{name} is using high CPU (#{cpu_perc})")
          end

          if mem_val > 80.0 do
            Logger.warning("Resource Alert: Container #{name} is using high Memory (#{mem_perc}), OOM kill risk!")
          end
        _ ->
          Logger.debug("Could not parse docker stats line: #{line}")
      end
    end)
  end

  defp parse_percentage(perc_str) do
    perc_str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
