defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage via `docker stats --no-stream`.
  Logs warnings if limits (80%) are exceeded.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

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
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  def perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)
        {error_output, exit_code} ->
          Logger.error("Failed to run docker stats. Exit code: #{exit_code}. Output: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute docker command (possibly missing executable): #{Exception.message(e)}")
    end
  end

  defp parse_and_check(output) do
    lines = String.split(output, "\n", trim: true)

    # Drop header line
    lines = if length(lines) > 0, do: tl(lines), else: []

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2) |> String.trim_trailing("%")
        mem_str = Enum.at(parts, 4) |> String.trim_trailing("%")

        cpu = parse_float(cpu_str)
        mem = parse_float(mem_str)

        if cpu > 80.0 do
          Logger.warning("Container #{container_id} CPU usage is high: #{cpu}%")
        end

        if mem > 80.0 do
          Logger.warning("Container #{container_id} Memory usage is high: #{mem}% (Risk of OOM Kill)")
        end
      end
    end)
  end

  defp parse_float(str) do
    case Float.parse(str) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
