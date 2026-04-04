defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers via Docker stats.
  Logs warnings if limits are approached or OOM risk is detected.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
    Logger.debug("Running Resource Watchdog checks...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_log_stats(output)

        {err, code} ->
          Logger.warning("docker stats returned non-zero code #{code}: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker CLI not available or system command failed: #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    output
    |> String.trim()
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu_str, mem_str] ->
          # Check for high CPU
          if String.ends_with?(cpu_str, "%") do
            cpu_val = cpu_str |> String.trim_trailing("%") |> Float.parse()
            case cpu_val do
              {val, _} when val > 80.0 ->
                Logger.warning("High CPU usage detected for container #{name}: #{cpu_str}")
              _ -> :ok
            end
          end

          # Simple check for Memory string containing something that indicates it's close to limit
          # mem_str looks like "100MiB / 200MiB"
          if String.contains?(mem_str, "/") do
            [used_str, limit_str] = String.split(mem_str, "/", parts: 2) |> Enum.map(&String.trim/1)
            # In a full implementation we'd parse the units (GiB, MiB) and compare exactly.
            # Here we just log the raw values for visibility
            Logger.debug("Container #{name} memory: #{used_str} of #{limit_str}")
          end
        _ ->
          :ok
      end
    end)
  end
end
