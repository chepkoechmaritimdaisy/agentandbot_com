defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via docker stats.
  Logs warnings if resources exceed 80%.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every minute

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
          parse_and_evaluate(output)
        {error_msg, code} ->
          Logger.warning("Docker stats failed with code #{code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to run: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip header
    lines
    |> Enum.drop(1)
    |> Enum.each(fn line ->
      parts = String.split(line, ~r/\s{2,}/)
      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim("%")
        mem_str = Enum.at(parts, 4) |> String.trim("%")

        cpu = case Float.parse(cpu_str) do
          {val, _} -> val
          :error -> 0.0
        end

        mem = case Float.parse(mem_str) do
          {val, _} -> val
          :error -> 0.0
        end

        if cpu > 80.0 do
          Logger.warning("Resource Watchdog: Container #{container_id} CPU usage is high: #{cpu}%")
        end

        if mem > 80.0 do
          Logger.warning("Resource Watchdog: Container #{container_id} Memory usage is high: #{mem}%")
        end
      end
    end)
  end
end
