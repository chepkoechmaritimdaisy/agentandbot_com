defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage dynamically.
  """
  use GenServer
  require Logger

  @interval 60_000

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

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} -> parse_and_warn(output)
        {error_msg, _code} -> Logger.error("Failed to execute docker stats: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Docker command not found or other ErlangError: #{inspect(e)}")
    end
  end

  defp parse_and_warn(output) do
    # Skip the header line
    [_header | lines] = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        # parts: [CONTAINER ID, NAME, CPU %, MEM USAGE / LIMIT, MEM %]
        name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > 80.0 do
              Logger.warning("Container #{name} CPU usage is high: #{cpu}%")
            end
            if mem > 80.0 do
              Logger.warning("Container #{name} Memory usage is high: #{mem}% (OOM Risk)")
            end
          _ ->
            Logger.debug("Could not parse resource usage for container #{name}")
        end
      end
    end)
  end
end
