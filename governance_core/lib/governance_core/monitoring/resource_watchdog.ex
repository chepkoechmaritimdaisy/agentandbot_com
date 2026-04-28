defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Continuously monitors container CPU and RAM usage via docker stats.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp check_resources do
    Logger.debug("Running ResourceWatchdog check")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          parse_and_alert(output)
        {error_output, exit_code} ->
          Logger.error("docker stats failed with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker command: #{inspect(e)}")
    end
  end

  defp parse_and_alert(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      [name, cpu_str, mem_str] = String.split(line, ",")

      cpu = parse_percent(cpu_str)
      mem = parse_percent(mem_str)

      if cpu > 80.0 do
        Logger.warning("High CPU usage for container #{name}: #{cpu}%")
      end

      if mem > 80.0 do
        Logger.warning("High Memory usage for container #{name}: #{mem}%")
      end
    end)
  end

  defp parse_percent(str) do
    # Remove '%' and parse as float
    cleaned = String.replace(str, "%", "") |> String.trim()
    case Float.parse(cleaned) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
