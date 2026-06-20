defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and RAM usage dynamically via `docker stats`.
  Logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  # Default interval for checking stats
  @interval 60 * 1000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    schedule_check()
    {:ok, %{}}
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
          parse_and_evaluate_stats(output)
        {_, code} ->
          Logger.error("Docker stats failed with exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Drop header
    |> Enum.each(&evaluate_line/1)
  end

  defp evaluate_line(line) do
    # Example format:
    # CONTAINER ID   NAME     CPU %     MEM USAGE / LIMIT   MEM %     NET I/O   BLOCK I/O   PIDS
    # e9d52b...      name     0.10%     10MiB / 1GiB        1.00%     ...
    columns = String.split(line, ~r/\s{2,}/)

    if length(columns) >= 5 do
      container = Enum.at(columns, 1)
      cpu_str = Enum.at(columns, 2)
      mem_str = Enum.at(columns, 4)

      cpu_usage = parse_percentage(cpu_str)
      mem_usage = parse_percentage(mem_str)

      if cpu_usage > 80.0 do
        Logger.warning("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu_usage}%")
      end

      if mem_usage > 80.0 do
        Logger.warning("ResourceWatchdog: Container #{container} Memory usage is high: #{mem_usage}% (Risk of OOM kill)")
      end
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {float, _} -> float
      :error -> 0.0
    end
  end
end
