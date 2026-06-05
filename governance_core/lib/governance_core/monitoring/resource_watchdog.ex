defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and RAM usage by running
  `docker stats --no-stream`. It logs warnings if CPU or memory usage
  exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

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
        {output, 0} ->
          parse_and_check(output)
        {error_output, code} ->
          Logger.error("ResourceWatchdog docker stats failed with code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog failed to run docker stats (is docker installed?): #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        case Float.parse(cpu_str) do
          {cpu, _} when cpu > 80.0 ->
            Logger.warning("ResourceWatchdog: Container #{container_id} CPU usage is high: #{cpu}%")
          _ -> :ok
        end

        case Float.parse(mem_str) do
          {mem, _} when mem > 80.0 ->
            Logger.warning("ResourceWatchdog: Container #{container_id} Memory usage is high: #{mem}%")
          _ -> :ok
        end
      end
    end)
  end
end
