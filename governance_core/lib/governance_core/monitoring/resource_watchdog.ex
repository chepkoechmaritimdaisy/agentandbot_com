defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container resources and alerts if CPU or Memory usage exceeds 80%.
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
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_check(output)
        {error, _} -> Logger.error("ResourceWatchdog: Failed to get docker stats - #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog: Could not execute docker command - #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1) # Drop header

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu >= 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu}%")
            end
            if mem >= 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container} Memory usage is high: #{mem}%")
            end
          _ ->
            Logger.debug("ResourceWatchdog: Could not parse stats for #{container}")
        end
      end
    end)
  end
end
