defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage using docker stats.
  Logs warnings for containers exceeding quotas or at risk of OOM kills.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
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
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}:{{.CPUPerc}}:{{.MemPerc}}"]) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.each(&analyze_stats/1)
        {error_output, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp analyze_stats(line) do
    case String.split(line, ":") do
      [name, cpu, mem] ->
        cpu_val = parse_percentage(cpu)
        mem_val = parse_percentage(mem)

        if cpu_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{name} CPU usage high: #{cpu}")
        end

        if mem_val > 85.0 do
          Logger.warning("ResourceWatchdog: Container #{name} Memory usage high (OOM risk): #{mem}")
        end
      _ ->
        :ok
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
