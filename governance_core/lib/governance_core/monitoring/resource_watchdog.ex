defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  ResourceWatchdog GenServer.
  Monitors Docker container CPU and RAM usage and logs warnings if usage exceeds 80%.
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
    Logger.info("Starting ResourceWatchdog Check...")

    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_check(output)

        {error, _code} ->
          Logger.warning("docker stats returned an error: #{inspect(error)}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to execute docker stats: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    lines = String.split(output, "\n", trim: true)

    # Skip the header
    case lines do
      [_header | containers] ->
        Enum.each(containers, &check_container/1)
      _ ->
        :ok
    end
  end

  defp check_container(line) do
    parts = String.split(line, ~r/\s{2,}/)

    if length(parts) >= 5 do
      container_id_or_name = Enum.at(parts, 0)
      cpu_str = Enum.at(parts, 2)
      mem_str = Enum.at(parts, 4)

      check_metric(container_id_or_name, "CPU", cpu_str)
      check_metric(container_id_or_name, "Memory", mem_str)
    end
  end

  defp check_metric(container, type, value_str) do
    # Remove % and parse as float
    clean_val = String.replace(value_str, "%", "")

    case Float.parse(clean_val) do
      {val, _} when val > 80.0 ->
        Logger.warning("ResourceWatchdog: Container #{container} #{type} usage is critical at #{val}%")
      _ ->
        :ok
    end
  end
end
