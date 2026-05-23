defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker Swarm/K3s resource usage for agent workloads.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp perform_check do
    Logger.info("Checking Docker container resources...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {output, code} ->
          Logger.error("Failed to fetch docker stats (code #{code}): #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker stats. Is docker installed? Error: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip the header line
    case lines do
      [_header | container_lines] ->
        Enum.each(container_lines, &evaluate_container_line/1)
      _ ->
        Logger.warning("No docker stats output to parse.")
    end
  end

  defp evaluate_container_line(line) do
    columns = String.split(line, ~r/\s{2,}/)

    if length(columns) >= 5 do
      container = Enum.at(columns, 0)
      cpu_str = Enum.at(columns, 2) |> String.replace("%", "")
      mem_str = Enum.at(columns, 4) |> String.replace("%", "")

      case {Float.parse(cpu_str), Float.parse(mem_str)} do
        {{cpu, _}, {mem, _}} ->
          if cpu > 80.0 do
            Logger.warning("Container #{container} CPU usage exceeds 80%: #{cpu}%")
          end
          if mem > 80.0 do
            Logger.warning("Container #{container} Memory usage exceeds 80%: #{mem}%")
          end
        _ ->
          Logger.debug("Could not parse CPU/Memory float values from: CPU=#{cpu_str}, MEM=#{mem_str}")
      end
    end
  end
end
