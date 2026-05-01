defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer to periodically monitor Docker container resource usage.
  """
  use GenServer
  require Logger

  # Update interval in milliseconds (5 minutes)
  @interval 5 * 60 * 1000

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
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          parse_and_log_stats(output)

        {error, _code} ->
          Logger.error("ResourceWatchdog failed to get docker stats: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog encountered ErlangError: #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    output
    |> String.trim()
    |> String.split("\n")
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu_str, mem_str] ->
          cpu = parse_percentage(cpu_str)
          mem = parse_percentage(mem_str)

          if cpu > 80.0 do
            Logger.warning("Container #{name} has high CPU usage: #{cpu}%")
          end

          if mem > 80.0 do
            Logger.warning("Container #{name} has high Memory usage: #{mem}%")
          end

        _ ->
          Logger.error("ResourceWatchdog failed to parse line: #{line}")
      end
    end)
  end

  defp parse_percentage(perc_str) do
    perc_str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
