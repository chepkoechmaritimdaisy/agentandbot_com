defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors the CPU and RAM usage of Docker containers.
  It logs warnings if usage limits are exceeded or OOM risks are detected.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # Run every 5 minutes

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
    try do
      # Format: container_id, name, cpu_percent, memory_percent
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.ID}},{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.each(&process_stat_line/1)

        {_output, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats returned exit code #{exit_code}")
      end
    rescue
      e in ErlangError -> Logger.warning("ResourceWatchdog: failed to run docker stats. #{inspect(e)}")
    end
  end

  defp process_stat_line(line) do
    case String.split(line, ",") do
      [id, name, cpu_str, mem_str] ->
        cpu = parse_percent(cpu_str)
        mem = parse_percent(mem_str)

        if cpu > 90.0 do
          Logger.warning("ResourceWatchdog: High CPU usage on container #{name} (#{id}): #{cpu}%")
        end

        if mem > 90.0 do
          Logger.warning("ResourceWatchdog: High Memory usage/OOM risk on container #{name} (#{id}): #{mem}%")
        end

      _ ->
        Logger.warning("ResourceWatchdog: Failed to parse docker stats output line: #{line}")
    end
  end

  defp parse_percent(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {float_val, _} -> float_val
      :error -> 0.0
    end
  end
end
