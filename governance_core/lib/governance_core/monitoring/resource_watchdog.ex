defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that periodically checks Docker container CPU and RAM usage via docker stats.
  Logs a warning if usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute
  @threshold 80.0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {error_msg, code} ->
          Logger.debug("Docker stats command failed with code #{code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.debug("Docker command not available: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true)

    Enum.drop(lines, 1)
    |> Enum.each(fn line ->
      # Docker stats default output separates columns by multiple spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # Format usually: CONTAINER ID | NAME | CPU % | MEM USAGE / LIMIT | MEM % | NET I/O | BLOCK I/O | PIDS
        # With regex split:
        # 0: CONTAINER ID
        # 1: NAME
        # 2: CPU %
        # 3: MEM USAGE / LIMIT
        # 4: MEM %
        name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > @threshold do
              Logger.warning("ResourceWatchdog: Container #{name} CPU usage is high: #{cpu}%")
            end
            if mem > @threshold do
              Logger.warning("ResourceWatchdog: Container #{name} Memory usage is high: #{mem}% (OOM risk)")
            end
          _ ->
            :ok
        end
      end
    end)
  end
end
