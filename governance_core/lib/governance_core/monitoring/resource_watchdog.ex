defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000
  @limit_threshold 80.0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    Logger.info("ResourceWatchdog checking docker stats...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check_stats(output)

        {_output, _status} ->
          Logger.warning("ResourceWatchdog: docker stats command returned non-zero status")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Failed to run docker command: #{inspect(e)}")
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp parse_and_check_stats(output) do
    # Skip header
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        cpu_val = parse_percentage(cpu_str)
        mem_val = parse_percentage(mem_str)

        if cpu_val > @limit_threshold do
          Logger.warning("ResourceWatchdog: Container #{container_id} CPU usage high: #{cpu_val}%")
        end

        if mem_val > @limit_threshold do
          Logger.warning("ResourceWatchdog: Container #{container_id} Memory usage high: #{mem_val}%")
        end
      end
    end)
  end

  defp parse_percentage(str) do
    # Remove '%' and parse float
    cleaned = String.replace(str, "%", "")
    case Float.parse(cleaned) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
