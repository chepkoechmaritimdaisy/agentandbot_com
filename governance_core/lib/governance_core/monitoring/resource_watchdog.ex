defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via `docker stats --no-stream`
  and logs warnings if resource usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 60_000 # 1 minute

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

  def perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {error_output, code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Error executing docker command: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    # Skip header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # parts[0] = CONTAINER ID
        # parts[1] = NAME
        # parts[2] = CPU %
        # parts[3] = MEM USAGE / LIMIT
        # parts[4] = MEM %

        container_name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_name} CPU usage is high: #{cpu}%")
            end
            if mem > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_name} Memory usage is high: #{mem}%")
            end
          _ ->
            Logger.debug("ResourceWatchdog: Could not parse stats for #{container_name}")
        end
      end
    end)
  end
end
