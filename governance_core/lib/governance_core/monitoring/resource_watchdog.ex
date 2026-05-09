defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and Memory usage via `docker stats` and logs warnings if limits are exceeded.
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
    check_docker_stats()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_docker_stats do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_evaluate(output)

        {error_output, code} ->
          Logger.warning("docker stats returned non-zero code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run docker stats (is docker installed?): #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    # Skip the header line
    lines = output |> String.split("\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        container_name = Enum.at(parts, 1)
        cpu_str = Enum.at(parts, 2) |> String.replace("%", "")
        mem_str = Enum.at(parts, 4) |> String.replace("%", "")

        case {Float.parse(cpu_str), Float.parse(mem_str)} do
          {{cpu, _}, {mem, _}} ->
            if cpu > @threshold do
              Logger.warning("ResourceWatchdog: Container #{container_name} (#{container_id}) CPU usage critical: #{cpu}%")
            end

            if mem > @threshold do
              Logger.warning("ResourceWatchdog: Container #{container_name} (#{container_id}) Memory usage critical: #{mem}% (OOM Risk)")
            end

          _ ->
            Logger.debug("ResourceWatchdog: Could not parse stats for container #{container_name}")
        end
      end
    end)
  end
end
