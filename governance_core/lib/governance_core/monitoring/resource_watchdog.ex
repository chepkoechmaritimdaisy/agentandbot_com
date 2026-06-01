defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that periodically checks docker container resource usage
  (CPU and memory) and logs warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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

  defp perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {error_output, exit_code} ->
          Logger.warning("Docker stats command failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker stats. Is docker installed? Error: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip header
    lines
    |> Enum.drop(1)
    |> Enum.each(&process_container_line/1)
  end

  defp process_container_line(line) do
    # Docker stats output format (approximate):
    # CONTAINER ID   NAME      CPU %     MEM USAGE / LIMIT   MEM %     NET I/O     BLOCK I/O   PIDS
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id = Enum.at(parts, 0)
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit("CPU", container_id, name, cpu_str)
      check_limit("Memory", container_id, name, mem_str)
    end
  end

  defp check_limit(type, container_id, name, value_str) do
    # Value usually looks like "0.01%" or "1.5%"
    clean_val = String.replace(value_str, "%", "") |> String.trim()

    case Float.parse(clean_val) do
      {value, _} ->
        if value > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{name} (#{container_id}) #{type} usage is critical: #{value}%")
        end
      :error ->
        Logger.debug("Could not parse #{type} value: #{value_str}")
    end
  end
end
