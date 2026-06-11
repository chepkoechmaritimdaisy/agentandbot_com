defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage using docker stats.
  Logs warnings if usage exceeds 80%.
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
          lines = String.split(output, "\n", trim: true) |> Enum.drop(1) # Drop header
          Enum.each(lines, &parse_and_check_line/1)
        {error_output, code} ->
          Logger.error("ResourceWatchdog docker stats failed with code #{code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("ResourceWatchdog failed to execute docker: #{inspect(e)}")
    end
  end

  defp parse_and_check_line(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_metric(container, "CPU", cpu_str)
      check_metric(container, "Memory", mem_str)
    end
  end

  defp check_metric(container, name, value_str) do
    # Format typically "0.00%" or similar
    clean_val = String.replace(value_str, "%", "")

    case Float.parse(clean_val) do
      {val, _} when val > @threshold ->
        Logger.warning("ResourceWatchdog ALERT: #{container} #{name} usage is critical at #{val}%")
      _ ->
        :ok
    end
  end
end
