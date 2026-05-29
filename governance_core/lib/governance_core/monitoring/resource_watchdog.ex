defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors Docker Swarm / K3s agent resources via `docker stats`.
  Logs warnings if CPU or Memory usage exceeds limits to prevent OOM kills.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000
  @limit_percentage 80.0

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
        {error_out, code} ->
          Logger.warning("docker stats failed with code #{code}: #{error_out}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("docker cli not available: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # Split on 2 or more spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        cpu = parse_float(cpu_str)
        mem = parse_float(mem_str)

        if cpu > @limit_percentage do
          Logger.warning("High CPU usage detected on container #{container_id}: #{cpu}%")
        end

        if mem > @limit_percentage do
          Logger.warning("High Memory usage detected on container #{container_id}: #{mem}% (OOM risk!)")
        end
      end
    end)
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
