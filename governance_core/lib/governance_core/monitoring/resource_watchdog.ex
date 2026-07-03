defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically checks Docker container resource usage (CPU and RAM)
  and logs warnings if they exceed the 80% threshold, preventing OOM issues.
  """
  use GenServer
  require Logger

  @interval 30_000 # Check every 30 seconds
  @threshold 80.0

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

  defp perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate(output)
        {error_msg, code} ->
          Logger.error("Docker stats failed with code #{code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        # Typically :enoent if docker is not installed
        Logger.debug("ResourceWatchdog skipping check: docker executable not found (#{inspect(e)})")
    end
  end

  defp parse_and_evaluate(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # Format usually: CONTAINER ID, NAME, CPU %, MEM USAGE / LIMIT, MEM %
        name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > @threshold do
              Logger.warning("ResourceWatchdog Alert: Container '#{name}' high CPU usage (#{cpu}%)")
            end

            if mem > @threshold do
              Logger.warning("ResourceWatchdog Alert: Container '#{name}' high RAM usage (#{mem}%) - OOM Risk!")
            end
          _ ->
            :ok
        end
      end
    end)
  end
end
