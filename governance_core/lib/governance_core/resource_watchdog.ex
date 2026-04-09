defmodule GovernanceCore.ResourceWatchdog do
  @moduledoc """
  Monitors container CPU and RAM usage by executing `docker stats` dynamically.
  Logs warnings for containers exceeding safe resource limits (OOM/Over-usage risk).
  Does not write to the filesystem, uses Logger instead.
  """
  use GenServer
  require Logger

  # 15 seconds monitoring interval
  @interval 15_000

  # Safe limits before warning
  @cpu_limit 80.0
  @mem_limit_mb 512.0

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_state) do
    schedule_check()
    {:ok, %{}}
  end

  def handle_info(:check, state) do
    case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
      {output, 0} ->
        process_stats(output)

      {err, _code} ->
        Logger.error("Resource Watchdog failed to get docker stats: #{err}")
    end

    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp process_stats(output) do
    lines = String.split(output, "\n", trim: true)

    Enum.each(lines, fn line ->
      case String.split(line, ",") do
        [name, cpu_str, mem_str] ->
          cpu = parse_cpu(cpu_str)
          mem_mb = parse_mem(mem_str)

          if cpu > @cpu_limit do
            Logger.warning("Container #{name} CPU usage is high: #{cpu}%")
          end

          if mem_mb > @mem_limit_mb do
            Logger.warning("Container #{name} RAM usage is high: #{mem_mb}MB - OOM risk!")
          end

        _ ->
          :ok
      end
    end)
  end

  defp parse_cpu(cpu_str) do
    cleaned = String.replace(cpu_str, "%", "")
    case Float.parse(cleaned) do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_mem(mem_str) do
    # Sample format: "250.5MiB / 1GiB"
    [usage | _rest] = String.split(mem_str, " /")
    cleaned = String.replace(usage, ~r/[a-zA-Z]/, "")

    # Very rudimentary parsing, assumes mostly MiB or converts naive value
    case Float.parse(cleaned) do
      {val, _} -> val
      :error -> 0.0
    end
  end
end
