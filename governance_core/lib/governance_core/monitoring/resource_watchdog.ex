defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via `docker stats`.
  Logs warnings if containers exceed isolated resource quotas (80% thresholds).
  """
  use GenServer
  require Logger

  # Check every 5 minutes
  @interval 5 * 60 * 1000
  @threshold 80.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
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

  def check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)

        {error, _code} ->
          Logger.error("Failed to run docker stats: #{error}")
      end
    rescue
      e in ErlangError -> Logger.error("Docker command not available: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    # Skip the header row
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1)
    |> Enum.each(&evaluate_container_stat/1)
  end

  defp evaluate_container_stat(line) do
    columns = String.split(line, ~r/\s{2,}/)

    if length(columns) >= 5 do
      container_name = Enum.at(columns, 1)
      cpu_str = Enum.at(columns, 2) |> String.trim_trailing("%")
      mem_str = Enum.at(columns, 4) |> String.trim_trailing("%")

      with {cpu, _} <- Float.parse(cpu_str),
           {mem, _} <- Float.parse(mem_str) do
        if cpu > @threshold do
          Logger.warning("High CPU Usage! Container: #{container_name}, CPU: #{cpu}%")
        end

        if mem > @threshold do
          Logger.warning("High Memory Usage! Risk of OOM. Container: #{container_name}, MEM: #{mem}%")
        end
      else
        _ -> Logger.debug("Failed to parse floats from stats line: #{line}")
      end
    end
  end
end
