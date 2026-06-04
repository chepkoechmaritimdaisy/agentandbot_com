defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage dynamically via docker stats.
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
        {output, 0} ->
          lines = String.split(output, "\n", trim: true)
          # Skip header line
          Enum.each(Enum.drop(lines, 1), &parse_and_check_line/1)
        {error, code} ->
          Logger.error("Failed to run docker stats (code #{code}): #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_check_line(line) do
    parts = String.split(line, ~r/\s{2,}/)
    if length(parts) >= 5 do
      container_name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit("CPU", container_name, cpu_str)
      check_limit("Memory", container_name, mem_str)
    end
  end

  defp check_limit(type, container_name, value_str) do
    # Expected format like "1.5%" or "85.2%"
    cleaned = String.replace(value_str, "%", "")
    case Float.parse(cleaned) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("ResourceWatchdog Alert: Container #{container_name} #{type} usage is at #{val}% (>80%). Potential OOM risk or limit exceeded.")
        end
      :error ->
        :ok
    end
  end
end
