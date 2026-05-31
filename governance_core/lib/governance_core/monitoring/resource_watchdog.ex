defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  use GenServer
  require Logger

  @interval 60 * 1000 # Run every minute

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    {:ok, state}
  end

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
      case System.cmd("docker", ["stats", "--no-stream"]) do
        {output, 0} ->
          lines = String.split(output, "\n") |> Enum.drop(1) # Drop header

          Enum.each(lines, fn line ->
            if String.trim(line) != "" do
              parts = String.split(line, ~r/\s{2,}/)
              if length(parts) >= 5 do
                container = Enum.at(parts, 0)
                cpu_str = Enum.at(parts, 2)
                mem_str = Enum.at(parts, 4)

                check_usage(container, "CPU", cpu_str)
                check_usage(container, "Memory", mem_str)
              end
            end
          end)
        {error_output, exit_code} ->
          Logger.error("Failed to run docker stats (exit code #{exit_code}): #{error_output}")
      end
    rescue
      e in ErlangError -> Logger.warning("docker command not available: #{inspect(e)}")
    end
  end

  defp check_usage(container, type, usage_str) do
    # Remove % sign and parse to float
    usage_cleaned = String.replace(usage_str, "%", "")

    case Float.parse(usage_cleaned) do
      {usage, _} ->
        if usage > 80.0 do
          Logger.warning("ResourceWatchdog Alert: Container #{container} is using #{usage}% #{type} (exceeds 80% threshold).")
        end
      :error ->
        # It could be that memory is formatted differently depending on docker version, e.g. "100MiB / 2GiB"
        # We only really care about % here for simplicity per instructions, assuming % format
        :ok
    end
  end
end
