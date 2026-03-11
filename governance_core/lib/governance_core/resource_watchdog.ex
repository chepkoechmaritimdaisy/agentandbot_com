defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  A GenServer that monitors Docker container CPU and RAM usage dynamically using
  `docker stats` via `System.cmd`. Logs warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  @interval 60_000 # 1 minute
  @cpu_limit 80.0
  @mem_limit_mb 500.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_monitoring()
    {:ok, state}
  end

  def handle_info(:monitor, state) do
    perform_monitoring()
    schedule_monitoring()
    {:noreply, state}
  end

  defp schedule_monitoring do
    Process.send_after(self(), :monitor, @interval)
  end

  defp perform_monitoring do
    # Get stats for all containers, no-stream, custom format: "ID|Name|CPUPerc|MemUsage"
    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.ID}}|{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}"]) do
      {output, 0} ->
        parse_and_check(output)
      {error, _code} ->
        Logger.error("Resource Watchdog failed to get docker stats: #{error}")
    end
  end

  defp parse_and_check(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(&check_container/1)
  end

  defp check_container(line) do
    [id, name, cpu_str, mem_str] = String.split(line, "|")

    # CPU might have `%`
    cpu_val = parse_value(cpu_str)

    # MemUsage usually format "100MiB / 2GiB"
    mem_used_str = mem_str |> String.split("/") |> List.first() |> String.trim()
    mem_val = parse_mem(mem_used_str)

    if cpu_val > @cpu_limit do
      Logger.warning("Container #{name} (#{id}) exceeded CPU limit! CPU: #{cpu_val}%")
    end

    if mem_val > @mem_limit_mb do
      Logger.warning("Container #{name} (#{id}) exceeded Memory limit! Mem: #{mem_val}MB (Risk of OOM Kill)")
    end
  end

  defp parse_value(str) do
    str
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_mem(str) do
    # Basic conversion to MB for simple checking
    str = String.trim(str)
    cond do
      String.ends_with?(str, "GiB") ->
        parse_value(String.replace(str, "GiB", "")) * 1024.0
      String.ends_with?(str, "MiB") ->
        parse_value(String.replace(str, "MiB", ""))
      String.ends_with?(str, "KiB") ->
        parse_value(String.replace(str, "KiB", "")) / 1024.0
      String.ends_with?(str, "B") ->
        parse_value(String.replace(str, "B", "")) / (1024.0 * 1024.0)
      true ->
        parse_value(str)
    end
  end
end
