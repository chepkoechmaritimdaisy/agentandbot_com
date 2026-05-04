defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors CPU and RAM usage of containers using Docker stats to detect limit breaches or OOM risks.
  """
  use GenServer
  require Logger

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
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_log_stats(output)
        {error_output, exit_code} ->
          Logger.error("docker stats failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("docker command failed (perhaps not installed?): #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_limit(container, "CPU", cpu_str)
        check_limit(container, "Memory", mem_str)
      else
        Logger.warning("Unrecognized docker stats output format: #{line}")
      end
    end)
  end

  defp check_limit(container, type, percentage_str) do
    clean_str = String.replace(percentage_str, "%", "") |> String.trim()

    case Float.parse(clean_str) do
      {value, _} ->
        if value > 80.0 do
          Logger.warning("#{type} usage for container #{container} is high (#{value}%). Potential OOM/quota risk.")
        end
      :error ->
        Logger.warning("Could not parse #{type} percentage: #{percentage_str}")
    end
  end
end
