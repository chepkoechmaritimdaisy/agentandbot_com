defmodule GovernanceCore.Fuzzer do
  @moduledoc """
  A GenServer that continuously tests the robustness of the ClawSpeak and UMP parsers
  by feeding them random binary data. This ensures the application can gracefully handle
  inconsistent or malformed traffic without crashing.
  """
  use GenServer
  require Logger

  alias GovernanceCore.Protocols.ClawSpeak
  alias GovernanceCore.Protocols.UMP.Parser, as: UMPParser
  alias GovernanceCore.Protocols.UMP

  # Test every 5 seconds
  @interval 5_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_fuzz()
    {:ok, state}
  end

  def handle_info(:fuzz, state) do
    perform_fuzz()
    schedule_fuzz()
    {:noreply, state}
  end

  defp schedule_fuzz do
    Process.send_after(self(), :fuzz, @interval)
  end

  defp perform_fuzz do
    # Generate random binary data of lengths between 1 and 1024 bytes
    length = Enum.random(1..1024)
    random_data = :crypto.strong_rand_bytes(length)

    # Attempt to decode as ClawSpeak
    try do
      case ClawSpeak.decode(random_data) do
        {:ok, struct, _rest} ->
          # If it happens to be valid ClawSpeak, try parsing the arg as UMP
          _ = UMP.parse(struct.arg)
          :ok
        {:error, _reason} ->
          :ok
      end
    rescue
      e -> Logger.error("Fuzzer found ClawSpeak crash: #{inspect(e)}")
    end

    # Attempt to decode as UMP frame
    try do
      _ = UMPParser.parse_frame(random_data)
      :ok
    rescue
      e -> Logger.error("Fuzzer found UMPParser crash: #{inspect(e)}")
    end

    # Attempt to parse as UMP JSON directly
    try do
      _ = UMP.parse(random_data)
      :ok
    rescue
      e -> Logger.error("Fuzzer found UMP JSON crash: #{inspect(e)}")
    end
  end
end
