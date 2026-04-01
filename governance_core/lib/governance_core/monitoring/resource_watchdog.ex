defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the resource quotas (CPU/RAM) of Agent containers
  running on Docker Swarm or K3s. It reports excessive usage or OOM risks.
  """
  use GenServer
  require Logger

  # Check every 5 minutes
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

  def perform_check do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {error_output, exit_code} ->
          Logger.warning("docker stats returned non-zero exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Docker executable not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, "|") do
        [name, cpu_str, mem_str] ->
          evaluate_container(name, cpu_str, mem_str)
        _ ->
          :ok
      end
    end)
  end

  defp evaluate_container(name, cpu_str, mem_str) do
    # Basic warning logs, can be expanded to alerting

    # cpu_str is typically like "0.54%"
    cpu_val = String.replace(cpu_str, "%", "") |> Float.parse()

    case cpu_val do
      {val, _} when val > 80.0 ->
        Logger.warning("Resource Watchdog Alert: Container #{name} is using high CPU: #{cpu_str}")
      _ ->
        :ok
    end

    # mem_str is like "100MiB / 2GiB" or just "100MiB"
    # Split by '/' to get the actual usage, ignoring the limit
    [usage | _rest] = String.split(mem_str, "/")
    usage = String.trim(usage)

    if String.contains?(usage, "GiB") do
        Logger.warning("Resource Watchdog Alert: Container #{name} has high memory usage: #{usage}")
    end
  end
end
