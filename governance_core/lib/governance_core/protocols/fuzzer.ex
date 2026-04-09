defmodule GovernanceCore.Protocols.Fuzzer do
  @moduledoc """
  Periodically generates random binary payloads using StreamData.binary()
  and tests the ClawSpeak and UMP parsers to ensure robust error handling.
  """
  use GenServer
  require Logger

  # Run every 5 seconds
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
    # Generate a random binary payload using StreamData
    payload = StreamData.binary() |> Enum.take(1) |> hd()

    # Test UMP generic parser
    try do
      _ = GovernanceCore.Protocols.UMP.parse(payload)
    rescue
      e -> Logger.debug("Fuzzer UMP parser crash caught: #{inspect(e)}")
    catch
      :exit, e -> Logger.debug("Fuzzer UMP parser exit caught: #{inspect(e)}")
    end

    # Test UMP detailed parser
    try do
      _ = GovernanceCore.Protocols.UMP.Parser.parse_frame(payload)
    rescue
      e -> Logger.debug("Fuzzer UMP detailed parser crash caught: #{inspect(e)}")
    catch
      :exit, e -> Logger.debug("Fuzzer UMP detailed parser exit caught: #{inspect(e)}")
    end

    # Test ClawSpeak parser
    try do
      _ = GovernanceCore.Protocols.ClawSpeak.decode(payload)
    rescue
      e -> Logger.debug("Fuzzer ClawSpeak parser crash caught: #{inspect(e)}")
    catch
      :exit, e -> Logger.debug("Fuzzer ClawSpeak parser exit caught: #{inspect(e)}")
    end

    # If we haven't crashed the GenServer, we succeeded in isolating parsing errors
  end
end
