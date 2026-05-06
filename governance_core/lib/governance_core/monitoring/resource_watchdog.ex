defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that monitors Docker container CPU and Memory usage.
  It logs warnings if usage exceeds 80%.
  """

  use GenServer
  require Logger

  @interval 60_000 # 1 minute
  @threshold 80.0

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
          parse_and_log(output)
        {error_msg, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with code #{exit_code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Failed to execute docker. Error: #{inspect(e)}")
    end
  end

  defp parse_and_log(output) do
    # Skip the header line
    lines = String.split(output, "\n", trim: true) |> Enum.drop(1)

    Enum.each(lines, fn line ->
      parts = String.split(line, ~r/\s{2,}/)

      if length(parts) >= 5 do
        container = Enum.at(parts, 0)
        cpu_str = Enum.at(parts, 2)
        mem_str = Enum.at(parts, 4)

        check_limit(container, "CPU", cpu_str)
        check_limit(container, "Memory", mem_str)
      end
    end)
  end

  defp check_limit(container, type, val_str) do
    # val_str looks like "0.00%"
    clean_val = String.replace(val_str, "%", "")

    case Float.parse(clean_val) do
      {val, _} when val > @threshold ->
        Logger.warning("ResourceWatchdog Alert: Container #{container} #{type} usage is at #{val_str} (> #{@threshold}%)!")
      _ ->
        :ok
    end
  end
end
