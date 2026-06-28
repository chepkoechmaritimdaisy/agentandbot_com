defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker Swarm or K3s containers CPU and RAM usage via `docker stats --no-stream`.
  Logs warnings if either usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
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
          lines = String.split(output, "\n", trim: true)
          # Skip header line
          Enum.each(Enum.drop(lines, 1), &parse_and_check_line/1)
        {error, _code} ->
          Logger.error("ResourceWatchdog: Failed to run docker stats: #{inspect(error)}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog: Error executing docker command: #{inspect(e)}")
    end
  end

  defp parse_and_check_line(line) do
    parts = String.split(line, ~r/\s{2,}/)
    if length(parts) >= 5 do
      container = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
      mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

      case {Float.parse(cpu_str), Float.parse(mem_str)} do
        {{cpu, _}, {mem, _}} ->
          if cpu > 80.0 do
            Logger.warning("ResourceWatchdog: Container #{container} CPU usage exceeds 80% (#{cpu}%)")
          end
          if mem > 80.0 do
            Logger.warning("ResourceWatchdog: Container #{container} Memory usage exceeds 80% (#{mem}%)")
          end
        _ ->
          :ok
      end
    end
  end
end
