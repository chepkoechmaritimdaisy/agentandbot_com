defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via Docker stats.
  Logs warnings if limits (e.g. 80%) are exceeded.
  """
  use GenServer
  require Logger

  # Continuous interval
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
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
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_check(output)
        {output, code} -> Logger.warning("docker stats exited with code #{code}: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker stats (is docker installed?): #{inspect(e)}")
      e ->
        Logger.error("Exception during resource check: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # First line is header, skip it
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_limit(container, "CPU", cpu_str)
        check_limit(container, "Memory", mem_str)
      end
    end)
  end

  defp check_limit(container, type, percentage_str) do
    # Clean string: "0.00%" -> 0.0
    clean_str = String.replace(percentage_str, "%", "") |> String.trim()

    case Float.parse(clean_str) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("RESOURCE WARNING: Container #{container} is using #{val}% #{type} (exceeds 80%)")
        end
      :error ->
        # If float parse fails, try int parse just in case
        case Integer.parse(clean_str) do
          {val, _} ->
             if val > 80 do
                Logger.warning("RESOURCE WARNING: Container #{container} is using #{val}% #{type} (exceeds 80%)")
             end
          :error -> :ok
        end
    end
  end
end
