defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage by running `docker stats --no-stream`.
  Logs warnings if usage exceeds 80%.
  """
  use GenServer
  require Logger

  # Run every 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

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
          Logger.warning("ResourceWatchdog: docker stats exited with code #{code}. Output: #{error_output}")
      end
    rescue
      e in ErlangError ->
        Logger.info("ResourceWatchdog: Could not run docker. This is expected if not in a docker environment. Reason: #{inspect(e)}")
    end
  end

  defp parse_and_check(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      # docker stats default output columns are separated by multiple spaces
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container_id = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_limit("CPU", container_id, cpu_str)
        check_limit("Memory", container_id, mem_str)
      end
    end)
  end

  defp check_limit(type, container_id, val_str) do
    # The value string often ends with '%'
    clean_str = String.replace(val_str, "%", "")

    case Float.parse(clean_str) do
      {val, _} ->
        if val > 80.0 do
          Logger.warning("ResourceWatchdog: #{type} usage for container #{container_id} is high: #{val}%")
        end
      :error ->
        # Couldn't parse, maybe it's not a percentage or format changed
        :ok
    end
  end
end
