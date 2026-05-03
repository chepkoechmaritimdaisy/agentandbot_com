defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage via 'docker stats'.
  Logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @threshold 80.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

  def handle_info(:check_resources, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {error_output, code} ->
          Logger.debug("docker stats exited with code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.debug("Could not run 'docker stats' (ErlangError): #{inspect(e)}")
      e ->
        Logger.debug("Failed to run 'docker stats': #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > @threshold do
          Logger.warning("Container #{container} CPU usage is high: #{cpu_str}")
        end

        if mem_val > @threshold do
          Logger.warning("Container #{container} Memory usage is high: #{mem_str}")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
