defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors CPU and RAM usage via `docker stats --no-stream`
  and logs warnings if limits are exceeded.
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
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log(output)
        {err, _code} ->
          Logger.warning("Docker stats command failed: #{inspect(err)}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker stats (is docker installed?): #{inspect(e)}")
      e ->
        Logger.error("Error running docker stats: #{inspect(e)}")
    end
  end

  defp parse_and_log(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip header line
    lines
    |> Enum.drop(1)
    |> Enum.each(fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container} CPU usage is high: #{cpu_val}%")
        end

        if mem_val > 80.0 do
          Logger.warning("ResourceWatchdog: Container #{container} Memory usage is high: #{mem_val}% (OOM Risk)")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    clean_str = String.replace(str, "%", "")
    case Float.parse(clean_str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
