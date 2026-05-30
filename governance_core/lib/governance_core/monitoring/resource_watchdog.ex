defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker resource limits to track CPU/RAM over-utilization for containers.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_watch()
    {:ok, state}
  end

  @impl true
  def handle_info(:watch, state) do
    perform_watch()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  def perform_watch do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {output, code} ->
          Logger.warning("Docker stats command failed with code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker command (ErlangError): #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    # Skip the header line and process the rest
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.each(&process_line/1)
  end

  defp process_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    # docker stats output roughly looks like:
    # CONTAINER ID   NAME     CPU %     MEM USAGE / LIMIT     MEM %     NET I/O     BLOCK I/O   PIDS
    # So split on double spaces usually gives length > 5
    if length(parts) >= 5 do
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit(name, "CPU", cpu_str)
      check_limit(name, "Memory", mem_str)
    end
  end

  defp check_limit(name, type, val_str) do
    case Float.parse(String.replace(val_str, "%", "")) do
      {val, _} when val > 80.0 ->
        Logger.warning("Resource Watchdog Alert: #{name} #{type} usage is at #{val}% (> 80%)")
      _ ->
        :ok
    end
  end
end
