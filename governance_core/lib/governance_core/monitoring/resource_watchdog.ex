defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage by calling 'docker stats'
  to detect potential resource limits or OOM risks.
  """
  use GenServer
  require Logger

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
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          analyze_stats(output)
        {output, code} ->
          Logger.warning("ResourceWatchdog 'docker stats' exited with non-zero code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog failed to run 'docker stats' (docker might not be installed): #{inspect(e)}")
    end
  end

  defp analyze_stats(output) do
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1) # Drop header

    Enum.each(lines, fn line ->
      # Docker stats line format is roughly: CONTAINER_ID NAME CPU% MEM USAGE/LIMIT MEM% ...
      case Regex.run(~r/(\S+)\s+(\S+)\s+([\d\.]+)%\s+.*?\s+([\d\.]+)%/, line) do
        [_, container_id, name, cpu_str, mem_str] ->
          {cpu, _} = Float.parse(cpu_str)
          {mem, _} = Float.parse(mem_str)

          if cpu > 80.0 do
            Logger.warning("ResourceWatchdog: Container #{name} (#{container_id}) CPU limit risk: #{cpu}%")
          end

          if mem > 80.0 do
            Logger.error("ResourceWatchdog: Container #{name} (#{container_id}) OOM risk! Memory usage: #{mem}%")
          end
        _ ->
          :ok
      end
    end)
  end
end
