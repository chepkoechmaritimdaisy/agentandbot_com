defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Resource Watchdog GenServer.
  Periodically monitors Docker container CPU and RAM usage.
  Logs warnings if usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
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
    Logger.info("[ResourceWatchdog] Checking container resources...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_stats(output)
        {error, code} ->
          Logger.error("[ResourceWatchdog] docker stats failed with code #{code}: #{error}")
      end
    rescue
      e in ErlangError ->
        Logger.error("[ResourceWatchdog] Failed to execute docker command: #{inspect(e)}")
    end
  end

  defp parse_stats(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true)

    if length(lines) > 1 do
      tl(lines)
      |> Enum.each(&parse_line/1)
    end
  end

  defp parse_line(line) do
    # docker stats output fields are separated by multiple spaces
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_limit(container, "CPU", cpu_str)
      check_limit(container, "Memory", mem_str)
    end
  end

  defp check_limit(container, type, val_str) do
    # e.g., "0.00%" -> "0.00"
    num_str = String.replace(val_str, "%", "")

    case Float.parse(num_str) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("[ResourceWatchdog] Container #{container} #{type} usage high: #{val_str}")
        end
      :error ->
        Logger.debug("[ResourceWatchdog] Could not parse #{type} value: #{val_str}")
    end
  end
end