defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage dynamically using
  `docker stats --no-stream` and logs warnings if resource usage exceeds 80%.
  """
  use GenServer
  require Logger

  # Check interval (e.g. 5 minutes)
  @check_interval 5 * 60 * 1000

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
    Process.send_after(self(), :check, @check_interval)
  end

  defp perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          parse_and_log_stats(output)
        {error_output, exit_code} ->
          Logger.warning("docker stats exited with code #{exit_code}: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to run docker stats (is docker installed?): #{inspect(e)}")
    end
  end

  defp parse_and_log_stats(output) do
    # Skip the header line
    lines = output |> String.trim() |> String.split("\n") |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        # CPU % is at index 2, e.g. "0.05%"
        cpu_str = Enum.at(parts, 2)
        # MEM % is at index 4, e.g. "0.10%"
        mem_str = Enum.at(parts, 4)

        check_limit("CPU", container, cpu_str)
        check_limit("Memory", container, mem_str)
      end
    end)
  end

  defp check_limit(resource, container, value_str) do
    # Remove the % sign and parse to float
    clean_str = String.replace(value_str, "%", "")

    case Float.parse(clean_str) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("#{resource} usage for container #{container} is above 80% (#{value_str})!")
        end
      :error ->
        Logger.warning("Failed to parse #{resource} value for container #{container}: #{value_str}")
    end
  end
end
