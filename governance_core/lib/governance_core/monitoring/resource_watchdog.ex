defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors container CPU and RAM usage via Docker stats.
  Logs warnings if agents are exceeding limits or risking OOM.
  """
  use GenServer
  require Logger

  # 5 minutes
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_check()
    {:ok, state}
  end

  @impl true
  def handle_info(:check_resources, state) do
    check_resources()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check_resources, @interval)
  end

  defp check_resources do
    try do
      # Format string parses container ID, CPU %, and Mem %
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.ID}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          process_stats(output)

        {_error_output, exit_code} ->
          Logger.warning("ResourceWatchdog: docker stats command failed with exit code #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: Failed to execute docker command. Is docker installed? Error: #{inspect(e)}")
    end
  end

  defp process_stats(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(fn line ->
      case String.split(line, ",") do
        [id, cpu_str, mem_str | _] ->
          check_thresholds(id, cpu_str, mem_str)

        _ ->
          Logger.debug("ResourceWatchdog: Unexpected docker stats output format: #{line}")
      end
    end)
  end

  defp check_thresholds(id, cpu_str, mem_str) do
    cpu = parse_percentage(cpu_str)

    if cpu > 90.0 do
      Logger.warning("ResourceWatchdog: Container #{id} is exceeding CPU threshold (Usage: #{cpu}%)")
    end

    # Check for OOM risk based on memory usage string
    # E.g., "10MiB / 20MiB"
    case String.split(mem_str, " / ") do
      [used_str, limit_str] ->
        used = parse_memory_value(used_str)
        limit = parse_memory_value(limit_str)

        if limit > 0 and (used / limit) > 0.9 do
          Logger.warning("ResourceWatchdog: Container #{id} is at high risk of OOM Kill (Memory: #{mem_str})")
        end

      _ ->
        :ok
    end
  end

  defp parse_percentage(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp parse_memory_value(str) do
    # Simple parser for Docker memory strings like "10MiB", "1GiB"
    cond do
      String.ends_with?(str, "GiB") -> parse_float_prefix(str, "GiB") * 1024 * 1024 * 1024
      String.ends_with?(str, "MiB") -> parse_float_prefix(str, "MiB") * 1024 * 1024
      String.ends_with?(str, "KiB") -> parse_float_prefix(str, "KiB") * 1024
      String.ends_with?(str, "B") -> parse_float_prefix(str, "B")
      true -> 0.0
    end
  end

  defp parse_float_prefix(str, suffix) do
    str
    |> String.replace(suffix, "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
