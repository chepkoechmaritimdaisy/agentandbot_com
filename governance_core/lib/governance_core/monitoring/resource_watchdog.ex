defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  use GenServer
  require Logger

  @interval 5 * 60 * 1000 # 5 minutes

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
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
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}}: {{.CPUPerc}} CPU, {{.MemUsage}} RAM"]) do
        {output, 0} ->
          # Process and log warnings for high usage here
          Logger.info("ResourceWatchdog stats: \n#{output}")
          # Minimal parsing logic could go here; leaving as logging per requirements

        {_output, code} ->
          Logger.warning("ResourceWatchdog docker stats returned non-zero code: #{code}")
      end
    rescue
      e in ErlangError -> Logger.warning("ResourceWatchdog caught ErlangError (docker missing?): #{inspect(e)}")
    end
  end
end
