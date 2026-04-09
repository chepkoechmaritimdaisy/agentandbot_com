defmodule GovernanceCore.Monitoring.ResourceWatchdog do
  @moduledoc """
  GenServer that periodically runs `docker stats` via `System.cmd` to monitor container CPU and RAM.
  Logs warnings if limits are exceeded.
  """
  use GenServer
  require Logger

  # Check every 1 minute
  @interval 60 * 1000
  # Example thresholds
  @cpu_limit 80.0
  @mem_limit_gb 2.0

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_check()
    Logger.info("GovernanceCore.Monitoring.ResourceWatchdog started.")
    {:ok, state}
  end

  def handle_info(:check, state) do
    perform_check()
    schedule_check()
    {:noreply, state}
  end

  defp schedule_check do
    Process.send_after(self(), :check, @interval)
  end

  defp perform_check do
    try do
      case System.cmd("docker", ["stats", "--no-stream", "--format", "{{.Name}},{{.CPUPerc}},{{.MemUsage}}"]) do
        {output, 0} ->
          parse_and_check(output)

        {error_msg, exit_code} ->
          Logger.warning("docker stats exited with code #{exit_code}: #{error_msg}")
      end
    rescue
      e in ErlangError ->
        Logger.warning("Could not run docker stats (ErlangError): #{inspect(e)}. Docker might not be installed or accessible.")
    end
  end

  defp parse_and_check(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.each(&check_container/1)
  end

  defp check_container(line) do
    [name, cpu_str, mem_str] = String.split(line, ",")

    # Simple parse logic
    cpu = parse_cpu(cpu_str)
    mem_gb = parse_mem(mem_str)

    if cpu > @cpu_limit do
      Logger.warning("ResourceWatchdog: Container #{name} CPU usage is high: #{cpu}%")
    end

    if mem_gb > @mem_limit_gb do
      Logger.warning("ResourceWatchdog: Container #{name} RAM usage is high, OOM kill risk: #{mem_gb}GiB")
    end
  end

  defp parse_cpu(cpu_str) do
    cpu_str
    |> String.replace("%", "")
    |> Float.parse()
    |> case do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp parse_mem(mem_str) do
    # mem_str looks like "50MiB / 2GiB"
    [usage | _] = String.split(mem_str, " / ")
    cond do
      String.ends_with?(usage, "GiB") ->
        {val, _} = Float.parse(String.replace(usage, "GiB", ""))
        val
      String.ends_with?(usage, "MiB") ->
        {val, _} = Float.parse(String.replace(usage, "MiB", ""))
        val / 1024.0
      String.ends_with?(usage, "KiB") ->
        {val, _} = Float.parse(String.replace(usage, "KiB", ""))
        val / (1024.0 * 1024.0)
      String.ends_with?(usage, "B") ->
        {val, _} = Float.parse(String.replace(usage, "B", ""))
        val / (1024.0 * 1024.0 * 1024.0)
      true ->
        0.0
    end
  end
end
