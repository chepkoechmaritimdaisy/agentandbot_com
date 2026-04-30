defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage via Docker stats.
  It logs warnings if resource usage exceeds 80%.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

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
    Logger.debug("Running ResourceWatchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemPerc}}"]) do
        {output, 0} ->
          parse_and_check_stats(output)
        {error_output, exit_code} ->
          Logger.warning("docker stats returned non-zero exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker command (ResourceWatchdog): #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [name, cpu_str, mem_str] ->
          cpu = parse_percentage(cpu_str)
          mem = parse_percentage(mem_str)

          if cpu > 80.0 or mem > 80.0 do
             Logger.warning("High resource usage detected for container '#{name}': CPU #{cpu}%, MEM #{mem}%")
          end
        _ ->
          :ok
      end
    end)
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
