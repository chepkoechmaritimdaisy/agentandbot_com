defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage dynamically via `docker stats`.
  Logs warnings for high usage. Handles missing docker gracefully.
  """
  use GenServer
  require Logger

  @interval 60_000 # Check every minute

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
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
      {output, 0} = System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"])

      lines = String.split(output, "\n", trim: true)
      Enum.each(lines, fn line ->
        [name, cpu_str, mem_str] = String.split(line, "\t")

        # Parse CPU percentage
        cpu_perc =
          case Float.parse(String.trim_trailing(cpu_str, "%")) do
            {val, _} -> val
            :error -> 0.0
          end

        # Naive memory check (just looking for large GB values for warning)
        # e.g. "1.5GiB / 2GiB"

        if cpu_perc > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{name} has high CPU usage: #{cpu_str}")
        end

        if String.contains?(mem_str, "GiB") do
           # Very basic check, if memory is in GiB we might be using a lot
           # A more robust check would parse the actual MB/GB values
           Logger.warning("ResourceWatchdog: Container #{name} is using a lot of memory: #{mem_str}")
        end
      end)

    rescue
      e in ErlangError ->
        case e do
          %ErlangError{original: :enoent} ->
            Logger.warning("ResourceWatchdog: `docker` command not found. Skipping resource checks.")
          _ ->
            Logger.error("ResourceWatchdog: Failed to execute docker command: #{inspect(e)}")
        end
    end
  end
end
