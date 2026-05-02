defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker container resources (CPU and Memory) dynamically.
  Logs warnings if usage exceeds the 80% threshold.
  """

  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @threshold 80.0

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

  def check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)
        {error_output, exit_code} ->
          Logger.warning("Docker stats failed with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run docker stats (is docker installed?): #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Drop the header row
    |> Enum.each(&parse_line/1)
  end

  defp parse_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      cpu = parse_percentage(cpu_str)
      mem = parse_percentage(mem_str)

      if cpu > @threshold do
        Logger.warning("ResourceWatchdog: CPU usage for container #{name} is high: #{cpu}%")
      end

      if mem > @threshold do
        Logger.warning("ResourceWatchdog: Memory usage for container #{name} is high: #{mem}% (OOM risk)")
      end
    end
  end

  defp parse_percentage(str) do
    cleaned = String.replace(str, "%", "") |> String.trim()
    case Float.parse(cleaned) do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end
end
