defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage dynamically via docker stats,
  logging warnings if usage exceeds 80%.
  """

  use GenServer
  require Logger

  @interval 60 * 1000 # Run every 1 minute
  @threshold 80.0

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
          parse_and_check(output)
        {err, code} ->
          Logger.error("Failed to run docker stats: exit code #{code}, output: #{inspect(err)}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker CLI tool not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        # Assuming index 2 is CPU % and index 4 is Mem % based on typical docker stats output
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > @threshold do
          Logger.warn("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu_str}")
        end

        if mem_val > @threshold do
          Logger.warn("ResourceWatchdog: Container #{container} Memory usage is high: #{mem_str}")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    # Remove '%' and parse to float
    clean_str = String.replace(str, "%", "") |> String.trim()
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
