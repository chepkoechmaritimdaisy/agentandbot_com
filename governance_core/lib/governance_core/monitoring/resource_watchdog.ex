defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker Swarm or K3s containers resource usage (CPU and RAM) to prevent OOM kills and log resource quota violations.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every 1 minute
  @threshold_percent 80.0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
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
          parse_and_evaluate_stats(output)

        {error, _} ->
          Logger.warning("ResourceWatchdog: Failed to run docker stats: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Error executing docker command: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Drop header
    |> Enum.each(&evaluate_container/1)
  end

  defp evaluate_container(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id = Enum.at(parts, 0)
      name = Enum.at(parts, 1)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      cpu_usage = parse_percentage(cpu_str)
      mem_usage = parse_percentage(mem_str)

      if cpu_usage > @threshold_percent do
        Logger.warning("ResourceWatchdog [CPU ALERT]: Container #{name} (#{container_id}) usage at #{cpu_usage}%")
      end

      if mem_usage > @threshold_percent do
        Logger.warning("ResourceWatchdog [MEM ALERT]: Container #{name} (#{container_id}) usage at #{mem_usage}% - Risk of OOM kill")
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
