defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that continuously tracks Docker Swarm or K3s
  container CPU and RAM usage via `docker stats --no-stream`.
  Warns if limits exceed 80% to track resource isolation.
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
    Logger.info("Resource Watchdog checking Docker stats...")
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
        {output, 0} -> parse_and_check_stats(output)
        {error_output, code} ->
          Logger.warning("Docker stats exited with code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker stats (maybe docker is not installed): #{Exception.message(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Skip the header line
    |> Enum.each(&process_stat_line/1)
  end

  defp process_stat_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id = Enum.at(parts, 0)
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit(container_id, name, "CPU", cpu_str)
      check_limit(container_id, name, "Memory", mem_str)
    else
      Logger.debug("Malformed docker stats line: #{line}")
    end
  end

  defp check_limit(container_id, name, type, value_str) do
    # Remove percentage sign and parse float
    cleaned_str = String.replace(value_str, "%", "")

    case Float.parse(cleaned_str) do
      {value, _} when value > 80.0 ->
        Logger.warning("[RESOURCE WATCHDOG] Container #{name} (#{container_id}) #{type} usage is critically high: #{value_str}")
      {_, _} -> :ok
      :error -> Logger.debug("Could not parse #{type} value: #{value_str}")
    end
  end
end
