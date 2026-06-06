defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage using docker stats.
  Logs warnings if limits exceed 80%.
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

  defp perform_check do
    Logger.info("Starting Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)
        {error_msg, code} ->
          Logger.error("Failed to run docker stats (code #{code}): #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1) # Drop header

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_metric(container, "CPU", cpu_str)
        check_metric(container, "Memory", mem_str)
      end
    end)
  end

  defp check_metric(container, name, value_str) do
    # Remove % sign and parse as float
    cleaned = String.replace(value_str, "%", "")

    case Float.parse(cleaned) do
      {value, _} ->
        if value > 80.0 do
          Logger.warning("ResourceWatchdog: #{container} #{name} usage is at #{value}% (exceeds 80%)")
        end
      :error ->
        Logger.debug("ResourceWatchdog: Could not parse metric #{name} for #{container}")
    end
  end
end
