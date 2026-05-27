defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage by calling `docker stats`.
  Logs warnings if usage exceeds 80%.
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
          parse_and_check_stats(output)
        {error_output, exit_code} ->
          Logger.error("docker stats failed with exit code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_usage(container_id, "CPU", cpu_str)
        check_usage(container_id, "Memory", mem_str)
      end
    end)
  end

  defp check_usage(container_id, type, usage_str) do
    # Remove '%' and parse to float
    clean_str = String.replace(usage_str, "%", "")

    case Float.parse(clean_str) do
      {usage, _} ->
        if usage > 80.0 do
          Logger.warning("Resource Watchdog Alert: Container #{container_id} is using #{usage}% #{type} (exceeds 80% threshold). Risk of OOM kill or CPU throttling.")
        end
      :error ->
        Logger.debug("Could not parse #{type} usage for container #{container_id}: #{usage_str}")
    end
  end
end
