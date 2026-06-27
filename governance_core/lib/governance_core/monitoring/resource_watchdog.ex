defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer to monitor Docker container CPU and Memory limits.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
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
          lines = String.split(output, "\n", trim: true)
          # Skip header
          Enum.each(Enum.drop(lines, 1), &parse_and_check_line/1)
        {error, _code} ->
          Logger.error("Failed to run docker stats: #{error}")
      end
    rescue
      e in ErlangError -> Logger.error("Docker command not found or failed: #{inspect(e)}")
    end
  end

  defp parse_and_check_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit(container, "CPU", cpu_str)
      check_limit(container, "Memory", mem_str)
    end
  end

  defp check_limit(container, type, percentage_str) do
    case Float.parse(String.trim_trailing(percentage_str, "%")) do
      {val, _} when val > 80.0 ->
        Logger.warning("#{type} limit exceeded for container #{container}! Usage: #{percentage_str}")
      _ ->
        :ok
    end
  end
end
