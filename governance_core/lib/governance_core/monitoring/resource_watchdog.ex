defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via docker stats.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_watch()
    {:ok, state}
  end

  def handle_info(:watch, state) do
    perform_watch()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  def perform_watch do
    Logger.info("Starting ResourceWatchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)
        {output, exit_code} ->
          Logger.warning("docker stats exited with code #{exit_code}: #{output}")
      end
    rescue
      e in ErlangError -> Logger.warning("Failed to execute docker stats: #{inspect(e)}")
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

  defp check_metric(container, type, val_str) do
    # val_str might look like "0.00%" or "1.50%"
    clean_val = String.replace(val_str, "%", "")
    case Float.parse(clean_val) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("[ResourceWatchdog] High #{type} usage detected for container #{container}: #{val_str}")
        end
      :error ->
        nil
    end
  end
end
