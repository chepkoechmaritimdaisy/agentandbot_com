defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker Swarm or K3s agent container resource usage (CPU/RAM).
  Logs warnings if quotas are exceeded or there's OOM kill risk.
  """
  use GenServer
  require Logger

  @check_interval 60_000 # Check every minute
  @cpu_limit 80.0
  @ram_limit 80.0

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_check()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    do_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @check_interval)
  end

  defp do_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}} {{.CPUPerc}} {{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_evaluate(output)
        {error_msg, code} ->
          Logger.warning("ResourceWatchdog: docker stats failed with code #{code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("ResourceWatchdog: ErlangError invoking docker (perhaps missing binary?): #{inspect(e)}")
    end
  end

  defp parse_and_evaluate(output) do
    lines = String.split(String.trim(output), "\n")

    Enum.each(lines, fn line ->
      case String.split(line, " ", parts: 3) do
        [name, cpu_str, mem_str] ->
          cpu = parse_percentage(cpu_str)

          # Basic parsing for memory string, assuming format "Usage / Limit"
          mem =
            case String.split(mem_str, " / ") do
              [usage, limit] ->
                usage_bytes = parse_bytes(usage)
                limit_bytes = parse_bytes(limit)
                if limit_bytes > 0, do: (usage_bytes / limit_bytes) * 100, else: 0.0
              _ ->
                0.0
            end

          if cpu > @cpu_limit do
            Logger.warning("ResourceWatchdog: Container #{name} CPU usage high: #{Float.round(cpu, 2)}%")
          end

          if mem > @ram_limit do
            Logger.warning("ResourceWatchdog: Container #{name} RAM usage high (OOM kill risk): #{Float.round(mem, 2)}%")
          end

        _ ->
          :ok
      end
    end)
  end

  defp parse_percentage(str) do
    case Float.parse(String.trim_trailing(str, "%")) do
      {value, _} -> value
      :error -> 0.0
    end
  end

  defp parse_bytes(str) do
    # Simple parser for bytes string (e.g., "10MiB", "1GiB")
    str = String.trim(str)

    multiplier =
      cond do
        String.ends_with?(str, "GiB") -> 1024 * 1024 * 1024
        String.ends_with?(str, "MiB") -> 1024 * 1024
        String.ends_with?(str, "KiB") -> 1024
        String.ends_with?(str, "GB") -> 1000 * 1000 * 1000
        String.ends_with?(str, "MB") -> 1000 * 1000
        String.ends_with?(str, "KB") -> 1000
        String.ends_with?(str, "B") -> 1
        true -> 1
      end

    num_str = String.replace(str, ~r/[^0-9.]/, "")
    case Float.parse(num_str) do
      {val, _} -> val * multiplier
      :error -> 0.0
    end
  end
end
