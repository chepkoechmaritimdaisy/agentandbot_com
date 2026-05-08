defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer to monitor Docker resources (CPU and Memory).
  Uses `docker stats --no-stream` and logs warnings if usage exceeds 80%.
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
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    Logger.info("Running Resource Watchdog check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)
        {_, exit_code} ->
          Logger.warning("docker stats returned non-zero exit code: #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker stats (ErlangError): #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Split by 2 or more spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case Float.parse(cpu_str) do
          {cpu, _} when cpu > 80.0 -> Logger.warning("Container #{container} CPU usage is high: #{cpu}%")
          _ -> :ok
        end

        case Float.parse(mem_str) do
          {mem, _} when mem > 80.0 -> Logger.warning("Container #{container} Memory usage is high: #{mem}%")
          _ -> :ok
        end
      end
    end)
  end
end
