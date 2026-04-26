defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Watchdog for CPU and RAM isolation of running containers/agents.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
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
    watch_resources()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  defp watch_resources do
    Logger.info("ResourceWatchdog: Checking agent stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemPerc}}"]) do
        {output, 0} ->
          parse_and_log(output)
        {_output, exit_code} ->
          Logger.error("ResourceWatchdog: docker stats returned exit code #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog: docker command missing or failed: #{inspect(e)}")
    end
  end

  defp parse_and_log(output) do
    lines = String.split(output, "\n", trim: true)
    Enum.each(lines, fn line ->
      case String.split(line, "\t", trim: true) do
        [name, cpu_str, mem_str] ->
          cpu = parse_percentage(cpu_str)
          mem = parse_percentage(mem_str)
          if cpu > 80.0 or mem > 80.0 do
            Logger.warning("ResourceWatchdog: Alert! High usage on #{name} - CPU: #{cpu_str}, MEM: #{mem_str}")
          end
        _ ->
          Logger.debug("ResourceWatchdog: Unrecognized docker stats format: #{line}")
      end
    end)
  end

  defp parse_percentage(val_str) do
    clean_str = String.replace(val_str, "%", "") |> String.trim()
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
