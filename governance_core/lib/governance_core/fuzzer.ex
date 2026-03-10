defmodule GovernanceCore.Fuzzer do
  @moduledoc """
  Periodically generates random binary data to test ClawSpeak and UMP protocols.
  Logs errors if the decoding process crashes or behaves inconsistently.
  """
  use GenServer
  require Logger

  # Default interval: 5 seconds
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
    Logger.debug("Running protocol fuzzing...")

    # Generate random binary data for fuzzing
    random_bytes = :crypto.strong_rand_bytes(:rand.uniform(1024))

    try do
      # Test ClawSpeak.decode/1
      case GovernanceCore.Protocols.ClawSpeak.decode(random_bytes) do
        {:ok, _, _} -> :ok
        {:error, _} -> :ok # Handled errors are acceptable
        unexpected ->
          Logger.error("ClawSpeak decode returned inconsistent pattern: #{inspect(unexpected)}")
      end
    rescue
      e ->
        Logger.error("ClawSpeak decode crashed with exception: #{inspect(e)}")
    catch
      kind, value ->
        Logger.error("ClawSpeak decode crashed with #{kind}: #{inspect(value)}")
    end

    try do
      # Test UMP.parse/1
      case GovernanceCore.Protocols.UMP.parse(random_bytes) do
        {:ok, _} -> :ok
        {:error, _} -> :ok # Handled errors are acceptable
        unexpected ->
          Logger.error("UMP parse returned inconsistent pattern: #{inspect(unexpected)}")
      end
    rescue
      e ->
        Logger.error("UMP parse crashed with exception: #{inspect(e)}")
    catch
      kind, value ->
        Logger.error("UMP parse crashed with #{kind}: #{inspect(value)}")
    end
  end
end
