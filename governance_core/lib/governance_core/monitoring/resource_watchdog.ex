defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that continuously monitors container resources via `docker stats --no-stream`
  and logs warnings if CPU or memory usage exceeds 80%.
  """
  use GenServer
  require Logger

  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

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
          parse_and_check_stats(output)
        {_, _} ->
          Logger.warning("docker stats returned non-zero exit code.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("docker stats failed: #{inspect(e)}")
    end
  end

  defp parse_and_check_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop(1) # Drop header
    |> Enum.each(fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)

        cpu_str = Enum.at(parts, 2) |> String.trim("%")
        mem_str = Enum.at(parts, 4) |> String.trim("%")

        check_metric(container_id, "CPU", cpu_str)
        check_metric(container_id, "Memory", mem_str)
      end
    end)
  end

  defp check_metric(container_id, metric_name, value_str) do
    case Float.parse(value_str) do
      {val, _} when val > 80.0 ->
        Logger.warning("ResourceWatchdog Warning: Container #{container_id} #{metric_name} usage is high: #{val}%")
      _ ->
        :ok
    end
  end
end
