defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that monitors Docker container CPU and Memory usage.
  Logs warnings if limits (>80%) are exceeded.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

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
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_resources do
    Logger.debug("Running ResourceWatchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate_stats(output)
        {output, code} ->
          Logger.warning("docker stats returned non-zero code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("docker CLI not found or failed to execute: #{inspect(e)}")
    end
  end

  defp parse_and_evaluate_stats(output) do
    # Skip the header line
    lines = String.split(output, "\\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Docker stats output columns are separated by multiple spaces
      parts = String.split(line, ~r/\\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_id} CPU usage high: #{cpu}%")
            end
            if mem > 80.0 do
              Logger.warning("ResourceWatchdog: Container #{container_id} Memory usage high (OOM risk): #{mem}%")
            end
          _ ->
            Logger.debug("ResourceWatchdog: Could not parse stats for container #{container_id}")
        end
      end
    end)
  end
end
