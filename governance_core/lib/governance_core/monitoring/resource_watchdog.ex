defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  Periodically monitors Docker Swarm or K3s containers CPU and RAM usage.
  """
  use GenServer
  require Logger

  @interval 60 * 1000 # 1 minute

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_watch()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:watch, state) do
    check_resources()
    schedule_watch()
    {:noreply, state}
  end

  defp schedule_watch do
    Process.send_after(self(), :watch, @interval)
  end

  defp check_resources do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          analyze_output(output)
        {_output, code} ->
          Logger.warning("docker stats returned non-zero exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Failed to run docker command (ErlangError): #{inspect(e)}")
    end
  end

  defp analyze_output(output) do
    # Simple check for very high CPU (over 90%)
    lines = String.split(output, "\n", trim: true)
    Enum.each(lines, fn line ->
      case Regex.run(~r/:\s*([\d\.]+)%\s*CPU/, line) do
        [_, cpu_str] ->
          case Float.parse(cpu_str) do
            {cpu, _} when cpu > 90.0 ->
              Logger.warning("Resource Watchdog: High CPU usage detected: #{line}")
            _ -> :ok
          end
        _ -> :ok
      end
    end)
  end
end
